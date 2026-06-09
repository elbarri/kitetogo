defmodule Kite4rentWeb.PageControllerTest do
  use Kite4rentWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status == 200
  end

  test "GET /faq", %{conn: conn} do
    conn = get(conn, ~p"/faq")
    assert conn.status == 200
    assert html_response(conn, 200) =~ "Frequently Asked Questions"
  end

  test "GET /privacy-policy", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    assert conn.status == 200
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "GET /terms-of-service", %{conn: conn} do
    conn = get(conn, ~p"/terms-of-service")
    assert conn.status == 200
    assert html_response(conn, 200) =~ "Terms of Service"
  end

  test "GET /llms.txt", %{conn: conn} do
    conn = get(conn, ~p"/llms.txt")
    assert conn.status == 200
    assert response_content_type(conn, :text) =~ "text/plain"
    body = response(conn, 200)
    assert body =~ "# KiteToGo"
    assert body =~ "peer-to-peer kitesurfing"
    assert body =~ "## For LLM Agents"
  end

  test "GET /llms-full.txt", %{conn: conn} do
    conn = get(conn, ~p"/llms-full.txt")
    assert conn.status == 200
    assert response_content_type(conn, :text) =~ "text/plain"
    body = response(conn, 200)
    assert body =~ "# KiteToGo"
    assert body =~ "## Security Deposits"
    assert body =~ "## Rental Agreements"
    assert body =~ "## For LLM Agents"
  end
end
