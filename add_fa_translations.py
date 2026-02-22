import json
import sys
import os

filepath = 'bitchat/Localizable.xcstrings'
with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

translations = {
    "Choose an image": "انتخاب یک تصویر",
    "Select Image": "انتخاب تصویر",
    "Cancel": "لغو",
    "OK": "تأیید",
    "Close": "بستن",
    "Tap for library, long press for camera": "برای گالری ضربه بزنید، برای دوربین طولانی فشار دهید",
    "Choose photo": "انتخاب عکس",
    "Hold to record a voice note": "برای ضبط یادداشت صوتی نگه دارید"
}

strings = data.get("strings", {})

for en_key, fa_val in translations.items():
    if en_key not in strings:
        strings[en_key] = {
            "extractionState": "manual",
            "localizations": {}
        }
    
    if "localizations" not in strings[en_key]:
        strings[en_key]["localizations"] = {}
        
    strings[en_key]["localizations"]["fa"] = {
        "stringUnit": {
            "state": "translated",
            "value": fa_val
        }
    }

data["strings"] = strings

with open(filepath, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print("Updated Localizable.xcstrings!")
