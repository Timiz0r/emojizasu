#!/usr/bin/env python3
"""
Generate data/emoji.json from Unicode CLDR + custom slang annotations.

Run once: python3 scripts/generate_data.py
"""

import json
import os
import re
import urllib.request
import xml.etree.ElementTree as ET

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "picker", "data")
OUT_FILE = os.path.join(DATA_DIR, "emoji.json")

EMOJI_TEST_URL = "https://unicode.org/Public/emoji/15.1/emoji-test.txt"
CLDR_JA_URL = "https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/annotations/ja.xml"
CLDR_JA_DERIVED_URL = "https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/annotationsDerived/ja.xml"

# Category metadata: Unicode name -> (id, name_en_display, name_ja, icon)
CATEGORY_META = {
    "Smileys & Emotion":  ("smileys",   "Smileys & Emotion",  "顔・気持ち",   "😀"),
    "People & Body":      ("people",    "People & Body",      "人・ボディ",   "👋"),
    "Component":          None,  # skip
    "Animals & Nature":   ("animals",   "Animals & Nature",   "動物・自然",   "🐶"),
    "Food & Drink":       ("food",      "Food & Drink",       "食べ物・飲み物","🍎"),
    "Travel & Places":    ("travel",    "Travel & Places",    "旅行・場所",   "✈️"),
    "Activities":         ("activities","Activities",         "活動",         "⚽"),
    "Objects":            ("objects",   "Objects",            "物",           "💡"),
    "Symbols":            ("symbols",   "Symbols",            "記号・シンボル","❤️"),
    "Flags":              ("flags",     "Flags",              "旗",           "🏁"),
}

# Custom slang / alternate search terms
CUSTOM_TERMS: dict[str, dict] = {
    "🥺": {"keywords_ja": ["ぴえん","ぴえんぴえん","うるうる","かわいそう","悲しい","涙目"],
            "keywords_en": ["pleading","pien","sad","puppy eyes","begging"]},
    "😂": {"keywords_ja": ["草","ｗ","ｗｗｗ","笑える","ウケる","爆笑","大笑い"],
            "keywords_en": ["lmao","lol","crying laughing","dead","rofl","skull","hilarious"]},
    "💀": {"keywords_en": ["skull","dead","im dead","rip","lol","💀"],
            "keywords_ja": ["ドクロ","死ぬ","死んだ","終わった"]},
    "🔥": {"keywords_en": ["fire","lit","hot","flame","fiery","bussin"],
            "keywords_ja": ["炎上","バズる","アツい","燃える","熱い"]},
    "💯": {"keywords_en": ["100","perfect","real","truth","no cap","based"],
            "keywords_ja": ["100点","パーフェクト","ガチ","本当","マジ"]},
    "🤡": {"keywords_en": ["clown","fool","circus","cap","lying","clowning"],
            "keywords_ja": ["道化師","アホ","ピエロ","バカ"]},
    "😎": {"keywords_en": ["cool","sunglasses","chad","based","swag","sigma"],
            "keywords_ja": ["かっこいい","クール","チャド","イケてる"]},
    "🧢": {"keywords_en": ["cap","hat","lie","no cap","lying","cap emoji"],
            "keywords_ja": ["帽子","嘘","キャップ"]},
    "🙏": {"keywords_en": ["please","pray","thank you","hands","namaste","blessed","thanks"],
            "keywords_ja": ["お願い","ありがとう","祈り","よろしく","頼む","感謝"]},
    "💪": {"keywords_en": ["strong","flex","muscle","gains","strength","pow"],
            "keywords_ja": ["強い","筋肉","ガンバ","頑張って","力","ファイト"]},
    "🥰": {"keywords_en": ["love","cute","adorable","kawaii","smitten"],
            "keywords_ja": ["きゅん","かわいい","すき","好き","愛してる","萌え"]},
    "😍": {"keywords_en": ["love","heart eyes","beautiful","kawaii","obsessed"],
            "keywords_ja": ["かわいい","好き","ハートの目","きゅん","見惚れる"]},
    "😭": {"keywords_en": ["crying","sobbing","sad","devastated","not ok","bawling"],
            "keywords_ja": ["泣いてる","号泣","つらい","悲しい","しんどい","ぴえん"]},
    "😩": {"keywords_en": ["weary","tired","exhausted","stressed","ugh","done"],
            "keywords_ja": ["疲れた","つらい","しんどい","もうダメ","くたくた"]},
    "😫": {"keywords_en": ["tired","exhausted","weary","done","stressed","dead"],
            "keywords_ja": ["疲れた","しんどい","つらい","キツい","ヘトヘト"]},
    "🤌": {"keywords_en": ["chef kiss","perfect","italian","finger","muah"],
            "keywords_ja": ["完璧","サイコー","いい感じ","シェフキス"]},
    "✨": {"keywords_en": ["sparkle","magic","vibe","aesthetic","shiny","glitter"],
            "keywords_ja": ["キラキラ","ピカピカ","エモい","輝く","キラ"]},
    "🎉": {"keywords_en": ["party","celebrate","congrats","yay","woohoo","hype"],
            "keywords_ja": ["おめでとう","パーティー","祝い","わーい","乾杯"]},
    "💩": {"keywords_en": ["poop","shit","crap","poo","bs","garbage"],
            "keywords_ja": ["うんこ","くそ","クソ","うんち","💩"]},
    "😏": {"keywords_en": ["smirk","smug","doya","suspicious","sly","knowing"],
            "keywords_ja": ["ドヤ","ドヤ顔","得意げ","したり顔","してやったり"]},
    "👀": {"keywords_en": ["eyes","look","watching","sus","tea","stalking","side eye"],
            "keywords_ja": ["目","見てる","チェック","監視","凝視"]},
    "🙇": {"keywords_en": ["bow","sorry","apologize","japanese bow","apology"],
            "keywords_ja": ["ごめんなさい","申し訳ない","お詫び","よろしく","謝罪"]},
    "🤝": {"keywords_en": ["handshake","deal","agree","nice to meet","collab"],
            "keywords_ja": ["よろしく","握手","合意","取引","コラボ"]},
    "😔": {"keywords_en": ["sad","pensive","down","depressed","mood","lowkey sad"],
            "keywords_ja": ["悲しい","しょんぼり","元気ない","つらい","沈む"]},
    "🤗": {"keywords_en": ["hug","hugs","wholesome","warm","friendly","love"],
            "keywords_ja": ["ハグ","抱きしめる","嬉しい","ぎゅっと"]},
    "😊": {"keywords_en": ["smile","happy","blush","wholesome","warm"],
            "keywords_ja": ["にこにこ","笑顔","嬉しい","ほっこり","微笑み"]},
    "🐐": {"keywords_en": ["goat","greatest of all time","GOAT","legend","best","top"],
            "keywords_ja": ["ヤギ","最高","レジェンド","GOAT"]},
    "🍵": {"keywords_en": ["tea","drama","gossip","spill the tea","matcha","green tea"],
            "keywords_ja": ["お茶","抹茶","緑茶","ティー"]},
    "🧂": {"keywords_en": ["salt","salty","petty","bitter","extra","shade"],
            "keywords_ja": ["塩","塩辛い","ソルティ","冷たい"]},
    "👻": {"keywords_en": ["ghost","ghosting","spooky","boo","halloween","transparent"],
            "keywords_ja": ["ゴースト","おばけ","幽霊","無視する","消えた"]},
    "😒": {"keywords_en": ["side eye","unimpressed","whatever","annoyed","meh","unbothered"],
            "keywords_ja": ["うんざり","どうでも","めんどい","冷める"]},
    "🫡": {"keywords_en": ["salute","yes sir","respectfully","understood","roger"],
            "keywords_ja": ["敬礼","了解","分かりました","ラジャー"]},
    "🫠": {"keywords_en": ["melting","exhausted","suffering","hot","done","defeated"],
            "keywords_ja": ["溶けてる","ダメだ","死にそう","バテバテ","崩れる"]},
    "🫶": {"keywords_en": ["heart hands","love","wholesome","care","ily"],
            "keywords_ja": ["ハートの手","愛してる","大好き","ありがとう"]},
    "💅": {"keywords_en": ["nails","extra","unbothered","sassy","iconic","petty"],
            "keywords_ja": ["ネイル","気にしない","余裕","イケてる"]},
    "🗿": {"keywords_en": ["moai","stone face","emotionless","chad","sigma","deadpan","bruh"],
            "keywords_ja": ["モアイ","石の顔","無表情","ブルーハ"]},
    "⚡": {"keywords_en": ["lightning","fast","energy","zap","electric","power"],
            "keywords_ja": ["雷","稲妻","エネルギー","速い","ビリビリ"]},
    "🌸": {"keywords_en": ["cherry blossom","sakura","spring","japan","flower","hanami"],
            "keywords_ja": ["桜","さくら","春","花見","ハナミ"]},
    "🌊": {"keywords_en": ["wave","ocean","sea","surf","tsunami"],
            "keywords_ja": ["波","海","サーフィン","津波","大波"]},
    "🦋": {"keywords_en": ["butterfly","transformation","beautiful","flutter","change"],
            "keywords_ja": ["蝶","ちょうちょ","変身","変化","綺麗"]},
    "❤️": {"keywords_en": ["heart","love","red heart","ily","romance","love"],
            "keywords_ja": ["ハート","愛","好き","愛してる","恋","好き"]},
    "🖤": {"keywords_en": ["black heart","dark","goth","edgy","aesthetic"],
            "keywords_ja": ["黒ハート","ダーク","ゴス"]},
    "🫵": {"keywords_en": ["point","you","pointing","sus","accusation","calling out"],
            "keywords_ja": ["指す","あなた","そこ","指摘"]},
    "😤": {"keywords_en": ["triumph","smug","proud","snort","frustrated"],
            "keywords_ja": ["ムキー","怒り","フン","自信満々","鼻息"]},
    "😡": {"keywords_en": ["angry","mad","furious","rage","pissed","heated"],
            "keywords_ja": ["怒り","ムカつく","怒る","激怒","頭来た"]},
    "🥳": {"keywords_en": ["party face","celebrate","yay","birthday","hype","lit"],
            "keywords_ja": ["パーティー","誕生日","祝い","わーい","パーリー"]},
    "🥴": {"keywords_en": ["woozy","drunk","dizzy","confused","loopy","disoriented"],
            "keywords_ja": ["ふらふら","酔っぱらい","グルグル","クラクラ"]},
    "🥵": {"keywords_en": ["hot face","sweating","hot","spicy","thirsty"],
            "keywords_ja": ["暑い","汗だく","熱い","辛い","ホット"]},
    "🥶": {"keywords_en": ["cold face","freezing","cold","chilly"],
            "keywords_ja": ["寒い","凍える","冷たい","極寒"]},
    "😴": {"keywords_en": ["sleeping","zzz","tired","sleepy","goodnight","knocked out"],
            "keywords_ja": ["おやすみ","眠い","zzz","就寝","寝てる","ぐっすり"]},
    "🤣": {"keywords_en": ["rolling laughing","lmao","rofl","dead","hilarious","screaming"],
            "keywords_ja": ["爆笑","ウケる","草","笑える","転がる"]},
    "🤫": {"keywords_en": ["shush","secret","quiet","hush","shhh"],
            "keywords_ja": ["シー","内緒","秘密","静かに"]},
    "🤔": {"keywords_en": ["thinking","hmm","ponder","considering","sus"],
            "keywords_ja": ["考え中","うーん","考える","どうかな","検討"]},
    "😬": {"keywords_en": ["grimace","awkward","oof","yikes","cringe"],
            "keywords_ja": ["引きつる","ぎこちない","ヤバい","気まずい"]},
    "🤷": {"keywords_en": ["shrug","idk","dunno","whatever","no idea"],
            "keywords_ja": ["知らん","わからん","どうでも","シュラッグ"]},
    "🫂": {"keywords_en": ["people hugging","hug","comfort","support","wholesome"],
            "keywords_ja": ["抱擁","ハグ","慰め","サポート","温かい"]},
    "😈": {"keywords_en": ["devil","evil","mischievous","imp","naughty","chaotic"],
            "keywords_ja": ["悪魔","イタズラ","ワルい","邪悪","チャオティック"]},
    "👑": {"keywords_en": ["crown","king","queen","royalty","goat","legend","slay"],
            "keywords_ja": ["王冠","王様","女王","レジェンド","最高"]},
    "🌙": {"keywords_en": ["moon","night","crescent","nighttime","goodnight"],
            "keywords_ja": ["月","夜","三日月","おやすみ","夜空"]},
    "⭐": {"keywords_en": ["star","stars","favorite","wish","rate"],
            "keywords_ja": ["星","お気に入り","願い","スター","評価"]},
    "🎵": {"keywords_en": ["music","note","song","tune","bop","listen"],
            "keywords_ja": ["音楽","音符","歌","曲","ミュージック"]},
    "🍜": {"keywords_en": ["ramen","noodles","japanese food","noodle soup"],
            "keywords_ja": ["ラーメン","麺","うどん","そば","ヌードル"]},
    "🍣": {"keywords_en": ["sushi","japanese food","raw fish","wasabi"],
            "keywords_ja": ["寿司","すし","日本食","刺身","ワサビ"]},
    "🍙": {"keywords_en": ["rice ball","onigiri","japanese snack","riceball"],
            "keywords_ja": ["おにぎり","おむすび","海苔","具"]},
    "🍡": {"keywords_en": ["dango","japanese sweets","skewer","mochi"],
            "keywords_ja": ["だんご","和菓子","串","甘い"]},
    "⛩️": {"keywords_en": ["shrine","japan","torii","shinto","temple"],
            "keywords_ja": ["鳥居","神社","参拝","お参り","御朱印"]},
    "🗾": {"keywords_en": ["japan","japanese map","nippon"],
            "keywords_ja": ["日本","ニッポン","日本地図"]},
    "🏯": {"keywords_en": ["japanese castle","samurai","feudal","history"],
            "keywords_ja": ["城","日本城","お城","武士","侍"]},
    "🎌": {"keywords_en": ["japanese flags","japan","celebration"],
            "keywords_ja": ["日本の旗","日章旗","祭り","お祝い"]},
    "🉐": {"keywords_en": ["bargain","japanese","tokubetsu","special"],
            "keywords_ja": ["得","特","お得","スペシャル"]},
    "🀄": {"keywords_en": ["mahjong","game","tile","red dragon"],
            "keywords_ja": ["麻雀","マージャン","中","ゲーム"]},
}

KAOMOJI: list[dict] = [
    # Happy / Joy
    {"text": "(^▽^)", "name_en": "Happy", "name_ja": "ニコニコ", "tags": ["happy","smile","joy","嬉しい","笑顔","ニコニコ"]},
    {"text": "ヽ(^o^)丿", "name_en": "Cheering", "name_ja": "ウェーイ", "tags": ["cheer","happy","yay","嬉しい","ウェーイ","やった"]},
    {"text": "\\(≧▽≦)/", "name_en": "Overjoyed", "name_ja": "超嬉しい", "tags": ["joy","excited","yay","大喜び","超嬉しい"]},
    {"text": "(＾▽＾)", "name_en": "Happy Face", "name_ja": "笑顔", "tags": ["happy","smile","嬉しい","笑顔"]},
    {"text": "(ﾉ´∀｀)ﾉ", "name_en": "Joyful", "name_ja": "喜び", "tags": ["happy","joyful","喜び","嬉しい"]},
    {"text": "(*´▽`*)", "name_en": "Pleased", "name_ja": "にこにこ", "tags": ["pleased","happy","smile","にこにこ","笑顔"]},
    {"text": "ヾ(*´∀`*)ﾉ", "name_en": "Super Happy", "name_ja": "大喜び", "tags": ["happy","excited","嬉しい","大喜び"]},
    {"text": "(o^▽^o)", "name_en": "Gleeful", "name_ja": "嬉しい", "tags": ["happy","gleeful","嬉しい","喜ぶ"]},

    # Sad / Crying
    {"text": "(T_T)", "name_en": "Crying", "name_ja": "泣いてる", "tags": ["sad","cry","tears","悲しい","泣く","涙"]},
    {"text": "(;_;)", "name_en": "Weeping", "name_ja": "わーん", "tags": ["sad","cry","わーん","泣く","悲しい"]},
    {"text": "(っ◞‸◟c)", "name_en": "Sobbing", "name_ja": "号泣", "tags": ["sad","sob","cry","号泣","悲しい","泣く"]},
    {"text": "( ; ω ; )", "name_en": "Sad", "name_ja": "悲しい", "tags": ["sad","cry","悲しい","泣く"]},
    {"text": "(´；ω；`)", "name_en": "Tear-eyed", "name_ja": "うるうる", "tags": ["sad","cry","うるうる","涙目","ぴえん"]},
    {"text": "ヽ(;▽;)ノ", "name_en": "Wailing", "name_ja": "わーん", "tags": ["sad","cry","wail","泣く","わーん"]},

    # Angry
    {"text": "(╯°□°）╯︵ ┻━┻", "name_en": "Table Flip", "name_ja": "テーブルをひっくり返す", "tags": ["angry","flip","rage","rage quit","怒り","テーブルクロ"]},
    {"text": "┻━┻ ︵ヽ(`Д´)ﾉ︵ ┻━┻", "name_en": "Double Table Flip", "name_ja": "ダブルテーブルフリップ", "tags": ["angry","flip","rage","怒り","テーブル"]},
    {"text": "٩(ఠ益ఠ)۶", "name_en": "Furious", "name_ja": "激怒", "tags": ["angry","fury","rage","怒り","激怒","キレる"]},
    {"text": "(╬ Ò ‸ Ó)", "name_en": "Angry", "name_ja": "怒り", "tags": ["angry","mad","怒り","ムカつく"]},
    {"text": "(*`益´*)", "name_en": "Mad", "name_ja": "むかっ", "tags": ["angry","mad","むかっ","怒り"]},

    # Shy / Embarrassed
    {"text": "(〃>_<;〃)", "name_en": "Embarrassed", "name_ja": "恥ずかしい", "tags": ["shy","embarrassed","blush","恥ずかしい","照れ"]},
    {"text": "(*ノωノ)", "name_en": "Blushing", "name_ja": "照れ", "tags": ["blush","shy","照れ","恥ずかしい"]},
    {"text": "(*/ω\\*)", "name_en": "Hiding in Shame", "name_ja": "恥ずかしくて隠れる", "tags": ["shy","hide","embarrassed","照れ","隠れる"]},
    {"text": "(*^_^*)", "name_en": "Bashful", "name_ja": "照れ笑い", "tags": ["smile","shy","bashful","照れ笑い","恥ずかしい"]},

    # Confused / Surprised
    {"text": "(°ロ°)", "name_en": "Shocked", "name_ja": "ビックリ", "tags": ["shocked","surprised","びっくり","驚き","ビックリ"]},
    {"text": "(・・?)", "name_en": "Confused", "name_ja": "疑問", "tags": ["confused","question","疑問","わからない","？"]},
    {"text": "Σ(°△°|||)", "name_en": "Startled", "name_ja": "ギョッ", "tags": ["startled","shocked","ギョッ","ビックリ","驚き"]},
    {"text": "(⊙_⊙)", "name_en": "Wide-eyed", "name_ja": "目を丸くして", "tags": ["surprised","wide eyes","驚き","目が点"]},
    {"text": "(@_@)", "name_en": "Dazed", "name_ja": "目が回る", "tags": ["dizzy","dazed","目が回る","混乱"]},

    # Love / Affection
    {"text": "(♡˙︶˙♡)", "name_en": "Love", "name_ja": "ラブラブ", "tags": ["love","heart","ラブラブ","好き","愛"]},
    {"text": "(´ ▽`).。ｏ♡", "name_en": "Daydreaming of Love", "name_ja": "恋の夢想", "tags": ["love","dream","romance","恋","ラブ","夢"]},
    {"text": "(ノ*>∀<)ノ♡", "name_en": "Sending Love", "name_ja": "愛を送る", "tags": ["love","heart","送る","愛","ラブ"]},
    {"text": "♡( ◡‿◡ )", "name_en": "Adoring", "name_ja": "うっとり", "tags": ["love","adore","うっとり","好き"]},
    {"text": "(づ￣ ³￣)づ", "name_en": "Hugging", "name_ja": "ハグする", "tags": ["hug","love","ハグ","抱きつく","愛"]},
    {"text": "(づ。◕‿‿◕。)づ", "name_en": "Big Hug", "name_ja": "大ハグ", "tags": ["hug","cute","大ハグ","かわいい","ハグ"]},

    # Shrug / Indifferent
    {"text": "¯\\_(ツ)_/¯", "name_en": "Shrug", "name_ja": "どうしよ", "tags": ["shrug","idk","whatever","どうしよ","知らん","シュラッグ"]},
    {"text": "(・_・;)", "name_en": "Nervous Shrug", "name_ja": "困った", "tags": ["nervous","shrug","困った","どうしよ"]},

    # Cool / Smug
    {"text": "(•_•) ( •_•)>⌐■-■ (⌐■_■)", "name_en": "Deal With It", "name_ja": "かかってこい", "tags": ["cool","deal with it","sunglasses","かっこいい","クール"]},
    {"text": "( ͡° ͜ʖ ͡°)", "name_en": "Lenny Face", "name_ja": "レニー", "tags": ["lenny","look","creep","レニー","ニヤリ"]},
    {"text": "(￣ー￣)", "name_en": "Smug", "name_ja": "ドヤ", "tags": ["smug","cool","ドヤ","ニヤリ","してやったり"]},
    {"text": "(｀・ω・´)", "name_en": "Determined", "name_ja": "やる気", "tags": ["determined","confident","やる気","気合","ドヤ"]},

    # Cute / Animals
    {"text": "(=^ω^=)", "name_en": "Cat Face", "name_ja": "猫顔", "tags": ["cat","cute","かわいい","猫","ネコ"]},
    {"text": "(^･ω･^)", "name_en": "Happy Cat", "name_ja": "嬉しい猫", "tags": ["cat","happy","smile","猫","嬉しい"]},
    {"text": "( ̄(oo) ̄)", "name_en": "Pig", "name_ja": "ブタ", "tags": ["pig","animal","ブタ","豚"]},
    {"text": "( ・(ｴ)・ )", "name_en": "Bear", "name_ja": "クマ", "tags": ["bear","animal","クマ","熊"]},
    {"text": "ฅ(＾・ω・＾ฅ)", "name_en": "Kitty", "name_ja": "にゃん", "tags": ["cat","kitty","nyaa","にゃん","猫","ネコ"]},
    {"text": "(U ᵕ U❁)", "name_en": "Bunny", "name_ja": "ウサギ", "tags": ["bunny","rabbit","cute","ウサギ","かわいい"]},

    # Sleeping / Tired
    {"text": "(﹃ .)", "name_en": "Drooling / Sleepy", "name_ja": "よだれ", "tags": ["sleep","drool","tired","よだれ","眠い","睡眠"]},
    {"text": "(u_u)", "name_en": "Sleepy", "name_ja": "眠い", "tags": ["sleep","tired","眠い","おやすみ","zzz"]},
    {"text": "(-_-)zzZ", "name_en": "Sleeping", "name_ja": "すやすや", "tags": ["sleep","zzz","すやすや","眠い","おやすみ"]},
    {"text": "(。-ω-)zzZ", "name_en": "Fast Asleep", "name_ja": "グッスリ", "tags": ["sleep","deep sleep","グッスリ","おやすみ","ZZZ"]},

    # Misc / Fun
    {"text": "(ノ°▽°)ノ⌒♪", "name_en": "Singing", "name_ja": "歌ってる", "tags": ["music","sing","happy","歌","音楽","歌ってる"]},
    {"text": "ヾ(•ω•`)o", "name_en": "Waving", "name_ja": "バイバイ", "tags": ["wave","bye","バイバイ","さよなら","ばいばい"]},
    {"text": "(^_^)/~", "name_en": "Waving Goodbye", "name_ja": "またね", "tags": ["wave","bye","またね","バイバイ","さよなら"]},
    {"text": "m(_ _)m", "name_en": "Bowing", "name_ja": "お辞儀", "tags": ["bow","sorry","thank you","お辞儀","ありがとう","ごめんなさい"]},
    {"text": "(・∀・)", "name_en": "Grinning", "name_ja": "ニヤニヤ", "tags": ["smile","happy","grin","ニヤニヤ","笑う"]},
    {"text": "(´∀｀)", "name_en": "Carefree", "name_ja": "のほほん", "tags": ["carefree","relaxed","のほほん","ゆったり"]},
    {"text": "(´-ω-｀)", "name_en": "Somber", "name_ja": "しんみり", "tags": ["sad","quiet","しんみり","静か","落ち着いた"]},
    {"text": "(`・ω・´)ゞ", "name_en": "Saluting", "name_ja": "敬礼", "tags": ["salute","roger","敬礼","了解","はい"]},
    {"text": "(ΦωΦ)", "name_en": "Excited Eyes", "name_ja": "ワクワク", "tags": ["excited","eyes","ワクワク","楽しみ"]},
    {"text": "w(°o°)w", "name_en": "Amazed", "name_ja": "びっくり", "tags": ["amazed","wow","びっくり","すごい","ビックリ"]},
    {"text": "(；一_一)", "name_en": "Unimpressed", "name_ja": "しらけ", "tags": ["unimpressed","deadpan","しらけ","つまらない","冷める"]},
    {"text": "(¬_¬)", "name_en": "Side Eye", "name_ja": "横目", "tags": ["side eye","suspicious","横目","疑い","怪しい"]},
    {"text": "(○｀д´)ノシ", "name_en": "Scram!", "name_ja": "あっちいけ", "tags": ["angry","go away","あっちいけ","あっちへ行け","怒り"]},
    {"text": "φ(•ᴗ•○)", "name_en": "Writing", "name_ja": "メモ中", "tags": ["writing","note","メモ","書く","勉強"]},
    {"text": "(ﾉ*°▽°)ﾉ", "name_en": "Excited", "name_ja": "興奮", "tags": ["excited","happy","興奮","やったー"]},
    {"text": "ヽ(´▽｀)/", "name_en": "Delighted", "name_ja": "やったー", "tags": ["happy","joy","やったー","嬉しい","大喜び"]},
    {"text": "(*>ω<*)", "name_en": "Embarrassed & Happy", "name_ja": "照れ嬉しい", "tags": ["happy","shy","照れ嬉しい","かわいい"]},
]


def fetch(url: str) -> str:
    print(f"  Fetching {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "emojizasu-builder/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def parse_emoji_test(text: str) -> list[dict]:
    """Parse Unicode emoji-test.txt into list of {emoji, codepoints, name, group, subgroup}."""
    entries = []
    current_group = ""
    current_subgroup = ""
    for line in text.splitlines():
        if line.startswith("# group: "):
            current_group = line[9:].strip()
        elif line.startswith("# subgroup: "):
            current_subgroup = line[12:].strip()
        elif line and not line.startswith("#"):
            m = re.match(r"^([0-9A-F ]+)\s+;\s+fully-qualified\s+#\s+(\S+)\s+E[\d.]+\s+(.+)$", line)
            if m:
                codepoints, emoji_char, name = m.group(1).strip(), m.group(2), m.group(3).strip()
                entries.append({
                    "emoji": emoji_char,
                    "codepoints": codepoints,
                    "name_en": name,
                    "group": current_group,
                    "subgroup": current_subgroup,
                    "keywords_en": [],
                    "name_ja": "",
                    "keywords_ja": [],
                })
    return entries


def parse_cldr_annotations(xml_text: str) -> tuple[dict[str, str], dict[str, list[str]]]:
    """Return (tts_names, keywords) dicts keyed by emoji character."""
    tts: dict[str, str] = {}
    kws: dict[str, list[str]] = {}
    root = ET.fromstring(xml_text)
    for ann in root.iter("annotation"):
        cp = ann.get("cp", "")
        if not cp:
            continue
        text = (ann.text or "").strip()
        if ann.get("type") == "tts":
            tts[cp] = text
        else:
            # pipe-separated keywords
            kws[cp] = [k.strip() for k in text.split("|") if k.strip()]
    return tts, kws


def build_data() -> dict:
    print("Fetching emoji-test.txt ...")
    emoji_test = fetch(EMOJI_TEST_URL)
    entries = parse_emoji_test(emoji_test)
    print(f"  Parsed {len(entries)} fully-qualified emoji")

    print("Fetching CLDR Japanese annotations ...")
    ja_xml = fetch(CLDR_JA_URL)
    ja_names, ja_kws = parse_cldr_annotations(ja_xml)

    print("Fetching CLDR Japanese derived annotations ...")
    ja_derived_xml = fetch(CLDR_JA_DERIVED_URL)
    ja_names_d, ja_kws_d = parse_cldr_annotations(ja_derived_xml)

    # Merge derived into base (base takes priority)
    for k, v in ja_names_d.items():
        if k not in ja_names:
            ja_names[k] = v
    for k, v in ja_kws_d.items():
        if k not in ja_kws:
            ja_kws[k] = v

    # Apply Japanese data to entries
    for e in entries:
        ch = e["emoji"]
        if ch in ja_names:
            e["name_ja"] = ja_names[ch]
        if ch in ja_kws:
            e["keywords_ja"] = ja_kws[ch]

    # Apply custom slang terms
    for emoji_char, extra in CUSTOM_TERMS.items():
        for e in entries:
            if e["emoji"] == emoji_char:
                if "keywords_en" in extra:
                    e["keywords_en"] = list(dict.fromkeys(e["keywords_en"] + extra["keywords_en"]))
                if "keywords_ja" in extra:
                    e["keywords_ja"] = list(dict.fromkeys(e["keywords_ja"] + extra["keywords_ja"]))
                break

    # Build English keywords from name words
    for e in entries:
        name_words = re.findall(r"\w+", e["name_en"].lower())
        e["keywords_en"] = list(dict.fromkeys(name_words + e["keywords_en"]))

    # Group by category
    categories = []
    seen_groups: dict[str, dict] = {}
    for e in entries:
        g = e["group"]
        meta = CATEGORY_META.get(g)
        if meta is None:
            continue  # skip Components
        cat_id, name_en, name_ja, icon = meta
        if cat_id not in seen_groups:
            cat = {"id": cat_id, "name_en": name_en, "name_ja": name_ja, "icon": icon, "emoji": []}
            seen_groups[cat_id] = cat
            categories.append(cat)
        seen_groups[cat_id]["emoji"].append({
            "emoji": e["emoji"],
            "name_en": e["name_en"],
            "name_ja": e["name_ja"] or e["name_en"],
            "keywords_en": e["keywords_en"],
            "keywords_ja": e["keywords_ja"],
        })

    total = sum(len(c["emoji"]) for c in categories)
    print(f"  Total emoji across categories: {total}")
    return {"categories": categories, "kaomoji": KAOMOJI}


def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    data = build_data()
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    size_kb = os.path.getsize(OUT_FILE) // 1024
    print(f"\nWrote {OUT_FILE} ({size_kb} KB)")


if __name__ == "__main__":
    main()
