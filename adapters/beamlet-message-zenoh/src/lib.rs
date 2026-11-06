//! 静态 Zenoh 字节收发 Adapter, 不解释任务, 授权或执行结果

use thiserror::Error;
use zenoh::{
    Session,
    handlers::{FifoChannel, FifoChannelHandler},
    pubsub::{Publisher, Subscriber},
    qos::CongestionControl,
    sample::{Sample, SampleKind},
};

/// 应用消息大小与接收队列的独立上限
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Limits {
    max_message_bytes: usize,
    receive_capacity: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_message_bytes: 64 * 1024,
            receive_capacity: 16,
        }
    }
}

impl Limits {
    /// 创建正数上限, 不限制 Zenoh 自身所有内部缓冲区
    ///
    /// # 错误
    /// 任一上限为零时返回错误
    pub fn new(max_message_bytes: usize, receive_capacity: usize) -> Result<Self, Error> {
        if max_message_bytes == 0 || receive_capacity == 0 {
            return Err(Error::InvalidLimits);
        }
        Ok(Self {
            max_message_bytes,
            receive_capacity,
        })
    }
}

/// 已收到的传输消息, 保留路由地址而不解释业务负载
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct ReceivedMessage {
    /// 实际匹配的发布地址, 不是订阅通配表达式
    pub key_expr: String,
    /// 已通过应用字节上限检查的原始负载
    pub payload: Vec<u8>,
}

/// 持有一个接收地址的静态连接, 不做节点发现或业务重投
///
/// 接收队列满时向 Zenoh 施加背压, 不使用会静默覆盖数据的环形队列
/// 慢消费者可能阻塞 Zenoh 接收线程, 调用方应及时排空队列
#[derive(Debug)]
pub struct Transport {
    subscriber: Subscriber<FifoChannelHandler<Sample>>,
    session: Session,
    limits: Limits,
}

impl Transport {
    /// 在调用方静态配置的 TCP 地址监听
    ///
    /// # 错误
    /// 配置, 地址, 会话或接收地址声明失败时返回错误
    pub async fn listen(endpoint: &str, inbox: &str, limits: Limits) -> Result<Self, Error> {
        Self::open("peer", vec![endpoint], Vec::new(), inbox, limits).await
    }

    /// 作为 client 静态连接到指定的 peer 地址
    ///
    /// # 错误
    /// 配置, 地址, 连接或接收地址声明失败时返回错误
    pub async fn connect(endpoint: &str, inbox: &str, limits: Limits) -> Result<Self, Error> {
        Self::open("client", Vec::new(), vec![endpoint], inbox, limits).await
    }

    /// 按 Node 的静态拓扑创建 peer 会话, 监听和连接与业务角色无关
    ///
    /// # 错误
    /// 拓扑, 会话或订阅配置无效时返回错误
    pub async fn node(
        listen: &[String],
        connect: &[String],
        inbox: &str,
        limits: Limits,
    ) -> Result<Self, Error> {
        Self::open(
            "peer",
            listen.iter().map(String::as_str).collect(),
            connect.iter().map(String::as_str).collect(),
            inbox,
            limits,
        )
        .await
    }

    /// 在同一消息会话上创建独立的有界订阅, 不建立新网络连接
    ///
    /// # 错误
    /// 订阅配置或会话无效时返回错误
    pub async fn subscribe(&self, inbox: &str) -> Result<Self, Error> {
        let subscriber = self
            .session
            .declare_subscriber(inbox.to_owned())
            .with(FifoChannel::new(self.limits.receive_capacity))
            .await?;
        Ok(Self {
            subscriber,
            session: self.session.clone(),
            limits: self.limits,
        })
    }

    async fn open(
        mode: &str,
        listen: Vec<&str>,
        connect: Vec<&str>,
        inbox: &str,
        limits: Limits,
    ) -> Result<Self, Error> {
        let config = serde_json::json!({
            "mode": mode,
            "listen": { "endpoints": listen },
            "connect": { "endpoints": connect },
            "scouting": {
                "multicast": { "enabled": false },
                "gossip": { "enabled": false }
            }
        });
        let session = zenoh::open(zenoh::Config::from_json5(&config.to_string())?).await?;
        let subscriber = session
            .declare_subscriber(inbox.to_owned())
            .with(FifoChannel::new(limits.receive_capacity))
            .await?;
        Ok(Self {
            subscriber,
            session,
            limits,
        })
    }

    /// 为一个具体接收地址声明发送端, 不声明业务能力
    ///
    /// # 错误
    /// 接收地址无效或发送端声明失败时返回错误
    pub async fn sender(&self, target: &str) -> Result<Sender<'_>, Error> {
        let publisher = self
            .session
            .declare_publisher(target.to_owned())
            .congestion_control(CongestionControl::Block)
            .await?;
        Ok(Sender {
            publisher,
            max_message_bytes: self.limits.max_message_bytes,
        })
    }

    /// 接收一条 Put 消息, 在复制负载前检查应用字节上限
    ///
    /// # 错误
    /// 接收失败, 出现 Delete 或负载超限时返回错误
    pub async fn recv(&self) -> Result<Vec<u8>, Error> {
        Ok(self.recv_message().await?.payload)
    }

    /// 接收有界负载及实际发布地址, 供调用方区分回复路由
    ///
    /// # 错误
    /// 接收失败, 出现 Delete 或负载超限时返回错误
    pub async fn recv_message(&self) -> Result<ReceivedMessage, Error> {
        let sample = self.subscriber.recv_async().await?;
        if sample.kind() != SampleKind::Put {
            return Err(Error::UnexpectedDelete);
        }
        if sample.payload().len() > self.limits.max_message_bytes {
            return Err(Error::MessageTooLarge);
        }
        Ok(ReceivedMessage {
            key_expr: sample.key_expr().to_string(),
            payload: sample.payload().to_bytes().into_owned(),
        })
    }
}

/// 与接收地址绑定的发送端, 不得比所属 Transport 活得更久
#[derive(Debug)]
pub struct Sender<'a> {
    publisher: Publisher<'a>,
    max_message_bytes: usize,
}

impl Sender<'_> {
    /// 等待匹配的订阅者, 避免用固定睡眠猜测传输是否就绪
    ///
    /// 匹配只表示传输订阅存在, 不表示 Work 接纳或持久化
    /// 调用方负责设置等待超时
    ///
    /// # 错误
    /// 会话关闭或匹配监听失败时返回错误
    pub async fn wait_for_receiver(&self) -> Result<(), Error> {
        let listener = self.publisher.matching_listener().await?;
        if self.publisher.matching_status().await?.matching() {
            return Ok(());
        }
        loop {
            if listener.recv_async().await?.matching() {
                return Ok(());
            }
        }
    }

    /// 发送有界字节, 成功返回不代表业务接纳或执行成功
    ///
    /// # 错误
    /// 负载超限或 Zenoh 拒绝发送时返回错误, 不自动重新发送
    pub async fn send(&self, bytes: Vec<u8>) -> Result<(), Error> {
        if bytes.len() > self.max_message_bytes {
            return Err(Error::MessageTooLarge);
        }
        self.publisher.put(bytes).await?;
        Ok(())
    }
}

/// 传输或应用字节预算错误, 不代表业务执行失败
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum Error {
    /// 字节或队列上限为零
    #[error("传输资源上限必须为正数")]
    InvalidLimits,
    /// 应用消息超过配置上限
    #[error("消息超过传输字节上限")]
    MessageTooLarge,
    /// 本 Adapter 只接收 Put
    #[error("不支持删除类型的消息")]
    UnexpectedDelete,
    /// 底层 Zenoh 配置或 I/O 错误
    #[error("Zenoh 传输失败: {0}")]
    Zenoh(#[from] zenoh::Error),
}
