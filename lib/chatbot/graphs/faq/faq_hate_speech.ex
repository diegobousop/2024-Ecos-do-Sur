defmodule Chatbot.FaqHateSpeech do
  alias Chatbot.TelegramWrapper, as: TelegramWrapper
  alias Chatbot.HistoryFormatting
  alias Chatbot.CommonFunctions
  import ChatBot.Gettext

  @doc """
  This module represents the Hate Speech FAQ graph of the bot. It handles the behaviour of it till it reaches a solution
  or it enters another graph.
  """

  ##################################
  # START
  ##################################
  # 1 -----
  def resolve({:start, history, _}, user, key, _, message_id) do
    keyboard = [[%{text: gettext("HATE_SPEECH_RS_Q1"), callback_data: "Q1"}],
                [%{text: gettext("HATE_SPEECH_RS_Q2"), callback_data: "Q2"}],
                [%{text: gettext("HATE_SPEECH_RS_Q3"), callback_data: "Q3"}],
                [%{text: gettext("HATE_SPEECH_RS_Q4"), callback_data: "Q4"}],
                [%{text: gettext("HATE_SPEECH_RS_Q5"), callback_data: "Q5"}],
                [%{text: gettext("HATE_SPEECH_RS_Q6"), callback_data: "Q6"}],
                [%{text: gettext("HATE_SPEECH_RS_Q7"), callback_data: "Q7"}],
                [%{text: gettext("HATE_SPEECH_RS_Q8"), callback_data: "Q8"}],
                [%{text: gettext("BACK"), callback_data: "BACK"}]]
    new_history = [{:start, :faq_hate_speech} | history]
    TelegramWrapper.update_menu(keyboard, HistoryFormatting.buildMessage(gettext("HATE_SPEECH_RS_TITLE"), nil), user, message_id, key)
    {{:start_final_resolve, :faq_hate_speech}, new_history, nil}
  end

  def resolve({:start_final_resolve, history, _}, user, key,  "Q1", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q2", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q3", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q4", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q5", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q6", message_id), do:  resolve({:S2, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q7", message_id), do:  resolve({:S3, history, nil}, user, key, nil, message_id)
  def resolve({:start_final_resolve, history, _}, user, key, "Q8", message_id), do:  resolve({:S4, history, nil}, user, key, nil, message_id)

  ##################################
  # SOLUTIONS
  ##################################
  # S1 ---- (opciones 1-5)
  def resolve({:S1, _, _}, user, key, _, message_id), do:  CommonFunctions.do_finalize_simple(gettext("HATE_SPEECH_RS_S1"), user, message_id, key)
  # S2 ---- (opción 6)
  def resolve({:S2, _, _}, user, key, _, message_id), do:  CommonFunctions.do_finalize_simple(gettext("HATE_SPEECH_RS_S2"), user, message_id, key)
  # S3 ---- (opción 7)
  def resolve({:S3, _, _}, user, key, _, message_id), do:  CommonFunctions.do_finalize_simple(gettext("HATE_SPEECH_RS_S3"), user, message_id, key)

  # S4 ---- (opción 8 - muestra menú con dos opciones)
  def resolve({:S4, history, _}, user, key, _, message_id) do
    keyboard = [[%{text: gettext("HATE_SPEECH_RS_S4_BTN1"), callback_data: "HATE_CRIME"}],
                [%{text: gettext("HATE_SPEECH_RS_S4_BTN2"), callback_data: "PROTECTED_HATE"}],
                [%{text: gettext("BACK"), callback_data: "BACK"}]]
    new_history = [{:S4, :faq_hate_speech} | history]
    TelegramWrapper.update_menu(keyboard, HistoryFormatting.buildMessage(gettext("HATE_SPEECH_RS_S4"), nil), user, message_id, key)
    {{:S4_final_resolve, :faq_hate_speech}, new_history, nil}
  end

  def resolve({:S4_final_resolve, history, _}, user, key, "HATE_CRIME", message_id), do:  resolve({:S1, history, nil}, user, key, nil, message_id)
  def resolve({:S4_final_resolve, history, _}, user, key, "PROTECTED_HATE", message_id), do:  resolve({:S2, history, nil}, user, key, nil, message_id)
end
