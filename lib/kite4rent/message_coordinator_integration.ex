defmodule Kite4rent.MessageCoordinatorIntegration do
  @moduledoc """
  Example integration showing how to use MessageCoordinator in existing MessageProcessor.
  
  This demonstrates how to gradually migrate from LLMProcessor.process_text/2 
  to MessageCoordinator.process_text/2 with feature flags.
  """

  @doc """
  Drop-in replacement for LLMProcessor.process_text/2 calls.
  
  Usage in MessageProcessor.process_llm_content/4:
  
  # Before:
  LLMProcessor.process_text(text, llm_opts)
  
  # After (with feature flags):
  MessageCoordinatorIntegration.process_with_flags(text, llm_opts, %{
    use_intent_classifier: true,
    use_location_extractor: false,  # Enable in future checkpoint
    use_gear_extractor: false       # Enable in future checkpoint  
  })
  """
  def process_with_flags(text, opts, feature_flags) do
    # Merge feature flags into opts
    enhanced_opts = Keyword.put(opts, :feature_flags, feature_flags)
    
    Kite4rent.MessageCoordinator.process_text(text, enhanced_opts)
  end

  @doc """
  Conservative rollout - only use intent classifier, fallback for entities.
  
  This is the safest way to deploy Checkpoint 2.
  """
  def process_conservative(text, opts) do
    process_with_flags(text, opts, %{
      use_intent_classifier: true,   # ✅ Working and tested
      use_location_extractor: false, # ⏸️ Not implemented yet  
      use_gear_extractor: false      # ⏸️ Not implemented yet
    })
  end

  @doc """
  Full rollout - use all extractors (for future checkpoints).
  """
  def process_full(text, opts) do
    process_with_flags(text, opts, %{
      use_intent_classifier: true,  # ✅ Checkpoint 1 complete
      use_location_extractor: true, # 🎯 Checkpoint 3 target  
      use_gear_extractor: true      # 🎯 Checkpoint 4 target
    })
  end
end