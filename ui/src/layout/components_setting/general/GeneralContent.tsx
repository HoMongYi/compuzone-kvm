import { useState , useEffect } from "react";
import { Select } from "antd";
import {useReactAt} from 'i18n-auto-extractor/react'
import { isMobile } from "react-device-detect";

import { useJsonRpc } from "@/hooks/useJsonRpc";
import { SettingsPageHeader } from "@components/Settings/SettingsPageheader";
import notifications from "@/notifications";
import { useSettingsStore } from "@/hooks/stores";
import { SettingsItem } from "@components/Settings/SettingsView";
import enJSON from '@/locales/en.json';
import zhJSON from '@/locales/zh.json';
import koJSON from '@/locales/ko.json';
import { ThemeMode, useTheme } from "@/layout/contexts/ThemeContext";
import { dark_font_style } from "@/layout/theme_color";

const { Option } = Select;


export default function SettingsGeneral() {
  const [send] = useJsonRpc();
  const [autoUpdate, setAutoUpdate] = useState(true);
  const { $at, setCurrentLang } = useReactAt();

  // Theme and Language State
  const [theme, setTheme] = useState<string>('light');
  const { setThemeMode } = useTheme();
  const language = useSettingsStore(state => state.language);
  const setLanguage = useSettingsStore(state => state.setLanguage);

  useEffect(() => {
    send("getAutoUpdateState", {}, resp => {
      if ("error" in resp) return;
      setAutoUpdate(resp.result as boolean);
    });
  }, [send]);

  const langMap: Record<string, Record<string, string>> = { en: enJSON, zh: zhJSON, ko: koJSON };
  const getLangJSON = (lang: string) => langMap[lang] ?? enJSON;

  // Language Change Handler
  const handleLanguageChange = (value: string) => {
    setLanguage(value);
    setCurrentLang(value, getLangJSON(value));
  };

  // Initialize Language
  useEffect(() => {
    setCurrentLang(language, getLangJSON(language));
  }, [language, setCurrentLang]);

  // Theme Change Handler
  const handleThemeChange = (value: string) => {
    const root = document.documentElement;
    setThemeMode(value as ThemeMode)
    
    localStorage.setItem('theme', value);
    root.classList.remove('light', 'dark');
    root.classList.add(value);
    

    setTheme(value);
  };

  // Initialize Theme
  useEffect(() => {
    const savedTheme = localStorage.getItem('theme') || 'light';
    setTheme(savedTheme);

    const root = document.documentElement;
    
    root.classList.remove('light', 'dark');
    root.classList.add(savedTheme);
     
  }, [theme]);

  return (
    <div className="space-y-4 pb-[50px]">
      <SettingsPageHeader
        title={$at("General")}
        description={$at("Configure device settings and update preferences")}
      />
      <div className="space-y-4">
        <SettingsItem
          title={$at("Theme")}
          description={$at("Choose your preferred color theme")}
          className={`${isMobile ? "w-full flex-col" : ""}`}
        >
          <div className={`space-y-2 ${isMobile ? "w-full" : "w-[37%]"}`}>
            <Select
              value={theme}
              onChange={handleThemeChange}
              className={`!w-full !h-[36px]`}
            >
              <Option value="light" className={dark_font_style}>{$at('Light')}</Option>
              <Option value="dark" className={dark_font_style}>{$at('Dark')}</Option>
            </Select>
          </div>
        </SettingsItem>
      </div>

      <div className="space-y-4">
        <SettingsItem
          title={$at("Language")}
          description={$at("Choose your language")}
          className={`${isMobile ? "w-full flex-col" : ""}`}
        >
          <div className={`space-y-2 ${isMobile ? "w-full" : "w-[37%]"}`}>
            <Select
              value={language}
              onChange={handleLanguageChange}
              className={`!w-full !h-[36px]`}
            >
              <Option value="en" className={dark_font_style}>{$at('English')}</Option>
              <Option value="zh" className={dark_font_style}>{$at('中文')}</Option>
              <Option value="ko" className={dark_font_style}>한국어</Option>
            </Select>
          </div>
        </SettingsItem>
      </div>

    </div>
  );
}
