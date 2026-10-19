defmodule Beamlet.Web.PageHTML do
  @moduledoc """
  PageController 的模板容器，通过 embed_templates 编译相邻 page_html 模板；当前工作台使用独立 LiveView。

  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use Beamlet.Web, :html

  embed_templates "page_html/*"
end
