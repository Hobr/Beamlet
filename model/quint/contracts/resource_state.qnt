module resourceState {
  import normalUseProfile.* from "../beamletNormalUse"
  export normalUseProfile.*
  type Environment = { device: int, account: int, object: int, protocol: int }
  type ResourceBinding = ResourceUnbound | ResourceBound({ token: Token, environment: Environment })
  type ResourceCall = { token: Token, binding: ResourceBinding, actual: Environment }
  type ResourceContract = { environments: int -> Environment, bindings: int -> ResourceBinding,
    saved: List[ResourceBinding], calls: List[ResourceCall], changes: int }
  var resourceContract: ResourceContract
  pure val target: Environment = { device: 1, account: 1, object: 1, protocol: 1 }
  action resourceInit = all { normalInit, resourceContract' = {
    environments: Map(1 -> target, 2 -> { device: 2, account: 2, object: 2, protocol: 1 }),
    bindings: EXECUTIONS.mapBy(_ => ResourceUnbound), saved: List(), calls: List(), changes: 0 } }
  action holdResource = resourceContract' = resourceContract
}
