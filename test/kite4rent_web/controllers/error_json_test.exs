defmodule Kite4rentWeb.ErrorJSONTest do
  use Kite4rentWeb.ConnCase, async: true

  test "renders 404" do
    assert Kite4rentWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert Kite4rentWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
