defmodule Kite4rentWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use Kite4rentWeb, :controller` and
  `use Kite4rentWeb, :live_view`.
  """
  use Kite4rentWeb, :html

  embed_templates "layouts/*"
end
