import json
import sys
import os

filepath = 'bitchat/Localizable.xcstrings'
with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

translations = {
    "Mutual verification": "تأیید متقابل",
    "You and %@ verified each other": "شما و %@ یکدیگر را تأیید کردید",
    "Verified": "تأییدشده",
    "You verified %@": "شما %@ را تأیید کردید"
}

strings = data.get("strings", {})

for en_key, fa_val in translations.items():
    if en_key not in strings:
        strings[en_key] = {
            "localizations": {
                "en": {
                    "stringUnit": {
                        "state": "translated",
                        "value": en_key
                    }
                }
            }
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
