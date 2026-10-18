defmodule Beamlet.I18n.LocaleTest do
  use ExUnit.Case
  alias Beamlet.I18n
  alias Beamlet.I18n.{Locale, Vocabulary}

  describe "canonicalisation" do
    test "accepts the documented spellings" do
      for input <- ["zh_CN", "zh-CN", "zh-cn", "zh_cn", "zh", "cn", " ZH_cn "] do
        assert Locale.normalize(input) == "zh_CN",
               "expected #{inspect(input)} to canonicalise to zh_CN"
      end

      for input <- ["en", "en-US", "en-us", "en_US", "EN"] do
        assert Locale.normalize(input) == "en", "expected #{inspect(input)} to canonicalise to en"
      end
    end

    test "unknown and non-binary input never becomes a locale" do
      for input <- [nil, "", "klingon", "zh_TW", "fr", 42, :zh, ["en"]] do
        assert Locale.normalize(input) == nil, "expected #{inspect(input)} to be rejected"
      end
    end

    test "canonicalize/1 falls back to the shared default" do
      assert Locale.canonicalize("en") == "en"
      assert Locale.canonicalize("klingon") == "zh_CN"
      assert Locale.canonicalize(nil) == "zh_CN"
    end
  end

  describe "defaults and options" do
    test "Chinese is the shipped default" do
      assert Locale.default() == "zh_CN"
      assert Locale.locales() == ["zh_CN", "en"]
    end

    test "switcher options are labelled in their own language" do
      assert Locale.options() == [{"zh_CN", "中文"}, {"en", "English"}]
    end

    test "html lang values are valid BCP 47 tags" do
      assert Locale.html_lang("zh_CN") == "zh-CN"
      assert Locale.html_lang("en") == "en"
      assert Locale.html_lang("klingon") == "zh-CN"
      assert Locale.html_lang(nil) == "zh-CN"
    end
  end

  describe "put/1" do
    setup do
      Locale.put("zh_CN")
      on_exit(fn -> Locale.put("zh_CN") end)
    end

    test "installs the canonical locale for the current process" do
      assert Locale.put("en-US") == "en"
      assert Gettext.get_locale() == "en"
      assert I18n.gettext("running") == "running"
    end

    test "an unknown locale falls back to the default instead of leaking" do
      assert Locale.put("klingon") == "zh_CN"
      assert Gettext.get_locale() == "zh_CN"
      assert I18n.gettext("running") == "运行中"
    end
  end

  describe "vocabulary" do
    setup do
      Locale.put("zh_CN")
      on_exit(fn -> Locale.put("zh_CN") end)
    end

    test "translates only declared status and reason words" do
      assert Vocabulary.status(:running) == "运行中"
      assert Vocabulary.status("running") == "运行中"
      assert Vocabulary.reason(:timeout) == "超时"
      assert Vocabulary.reason("timeout") == "超时"

      Locale.put("en")
      assert Vocabulary.status(:running) == "running"
      assert Vocabulary.reason(:timeout) == "timeout"
    end

    test "unknown values keep their existing rendering instead of becoming copy" do
      assert Vocabulary.status(:not_a_status) == "not_a_status"
      assert Vocabulary.status("custom value") == "custom value"
      assert Vocabulary.reason(:not_a_reason) == "not_a_reason"
      assert Vocabulary.reason(nil) == nil
      assert Vocabulary.status(%{}) == %{}
    end
  end
end
