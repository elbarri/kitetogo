ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(Kite4rent.Repo, :manual)

# Start Mimic for mocking
Application.ensure_all_started(:mimic)

# Copy modules at compile time - these are the modules commonly mocked in tests
# IMPORTANT: Mimic.copy must be called ONCE per module, at compile time (not in setup blocks)
Mimic.copy(Kite4rent.Utils.HTTPClient)
Mimic.copy(Kite4rent.WhatsappClient)
Mimic.copy(Kite4rent.AudioProcessor)
Mimic.copy(Kite4rent.MessageCoordinatorIntegration)
Mimic.copy(Kite4rent.MediaStorage)
Mimic.copy(Kite4rent.Rental)
Mimic.copy(Kite4rent.Repo)
Mimic.copy(Kite4rent.Users)
Mimic.copy(Kite4rent.Messages)
Mimic.copy(Kite4rent.Payments)
Mimic.copy(Kite4rent.Geocoding)
Mimic.copy(Kite4rent.IntentionHandler)
Mimic.copy(Kite4rent.ReplyComposer)
Mimic.copy(Kite4rent.Deposits)
Mimic.copy(Kite4rent.LLMProcessor)
Mimic.copy(Kite4rent.LLM)
Mimic.copy(Kite4rent.StripeHelpers)
Mimic.copy(Stripe.Checkout.Session)
Mimic.copy(Stripe.Customer)
Mimic.copy(File)
Mimic.copy(Kite4rent.NominatimRateLimiter)
Mimic.copy(Kite4rent.Extractors.IntentClassifier)
Mimic.copy(Kite4rent.Extractors.LocationExtractor)
Mimic.copy(Kite4rent.Extractors.GearExtractor)
Mimic.copy(Kite4rent.Extractors.DepositExtractor)
Mimic.copy(Kite4rent.Translator)
Mimic.copy(Kite4rent.MessageProcessor)

# Global stub for HTTPClient to prevent any real API calls
# Tests that need specific HTTP behavior should use Mimic.expect/stub to override
Mimic.stub(Kite4rent.Utils.HTTPClient, :request, fn method, url, _headers, _body ->
  raise "Real HTTP call attempted! method=#{method} url=#{url} - This should be mocked in tests"
end)

# Global stub for WhatsappClient to prevent any real WhatsApp API calls
# Note: Functions with default args (opts \\ []) are always called with full arity
Mimic.stub(Kite4rent.WhatsappClient, :send_message, fn _phone, _msg, _extra_content ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
Mimic.stub(Kite4rent.WhatsappClient, :send_messages, fn _phone, _messages ->
  {:ok, [{:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}]}
end)
Mimic.stub(Kite4rent.WhatsappClient, :send_contact, fn _phone, _contact_id_or_data ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
# send_interactive_reply_buttons has opts \\ [] so always 4 args
Mimic.stub(Kite4rent.WhatsappClient, :send_interactive_reply_buttons, fn _phone, _body, _buttons, _opts ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
# send_interactive_cta_url has opts \\ [] so always 5 args
Mimic.stub(Kite4rent.WhatsappClient, :send_interactive_cta_url, fn _phone, _body, _btn_text, _url, _opts ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
# send_interactive_list has opts \\ [] so always 5 args
Mimic.stub(Kite4rent.WhatsappClient, :send_interactive_list, fn _phone, _body, _btn, _sections, _opts ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
Mimic.stub(Kite4rent.WhatsappClient, :send_location_request, fn _phone, _body, _extra ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
Mimic.stub(Kite4rent.WhatsappClient, :send_reaction, fn _phone, _msg_id, _emoji ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
# send_template has components \\ [] so always 4 args
Mimic.stub(Kite4rent.WhatsappClient, :send_template, fn _phone, _template, _lang, _components ->
  {:ok, %{"messages" => [%{"id" => "mock_msg_id"}]}}
end)
Mimic.stub(Kite4rent.WhatsappClient, :mark_message_read_and_show_typing, fn _phone, _msg_id ->
  :ok
end)
Mimic.stub(Kite4rent.WhatsappClient, :download_media, fn _media_id ->
  {:ok, "mock_media_data"}
end)
