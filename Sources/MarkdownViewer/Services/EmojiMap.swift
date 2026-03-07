import Foundation

enum EmojiMap {
    private static let shortcodeRegex = try! NSRegularExpression(pattern: #":([a-z0-9_]+):"#)

    static func convert(_ text: String) -> String {
        let ns = text as NSString
        let matches = shortcodeRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text as NSString
        for match in matches.reversed() {
            let code = ns.substring(with: match.range(at: 1))
            if let emoji = map[code] {
                result = result.replacingCharacters(in: match.range, with: emoji) as NSString
            }
        }
        return result as String
    }

    // ~200 most commonly used emoji shortcodes
    static let map: [String: String] = [
        // Smileys
        "smile": "\u{1F604}", "laughing": "\u{1F606}", "blush": "\u{1F60A}",
        "smiley": "\u{1F603}", "grinning": "\u{1F600}", "wink": "\u{1F609}",
        "heart_eyes": "\u{1F60D}", "kissing_heart": "\u{1F618}", "stuck_out_tongue": "\u{1F61B}",
        "stuck_out_tongue_winking_eye": "\u{1F61C}", "sunglasses": "\u{1F60E}",
        "smirk": "\u{1F60F}", "neutral_face": "\u{1F610}", "expressionless": "\u{1F611}",
        "unamused": "\u{1F612}", "sweat": "\u{1F613}", "pensive": "\u{1F614}",
        "confused": "\u{1F615}", "disappointed": "\u{1F61E}", "cry": "\u{1F622}",
        "sob": "\u{1F62D}", "joy": "\u{1F602}", "rofl": "\u{1F923}",
        "astonished": "\u{1F632}", "scream": "\u{1F631}", "angry": "\u{1F620}",
        "rage": "\u{1F621}", "triumph": "\u{1F624}", "sleepy": "\u{1F62A}",
        "sleeping": "\u{1F634}", "mask": "\u{1F637}", "thinking": "\u{1F914}",
        "shushing_face": "\u{1F92B}", "zipper_mouth": "\u{1F910}",
        "nerd_face": "\u{1F913}", "monocle_face": "\u{1F9D0}",
        "skull": "\u{1F480}", "ghost": "\u{1F47B}", "alien": "\u{1F47D}",
        "robot": "\u{1F916}", "clown_face": "\u{1F921}", "eyes": "\u{1F440}",
        "brain": "\u{1F9E0}", "tongue": "\u{1F445}",

        // Gestures
        "thumbsup": "\u{1F44D}", "+1": "\u{1F44D}", "thumbsdown": "\u{1F44E}",
        "-1": "\u{1F44E}", "ok_hand": "\u{1F44C}", "wave": "\u{1F44B}",
        "clap": "\u{1F44F}", "raised_hands": "\u{1F64C}", "pray": "\u{1F64F}",
        "handshake": "\u{1F91D}", "muscle": "\u{1F4AA}", "point_up": "\u{261D}\u{FE0F}",
        "point_down": "\u{1F447}", "point_left": "\u{1F448}", "point_right": "\u{1F449}",
        "middle_finger": "\u{1F595}", "v": "\u{270C}\u{FE0F}", "metal": "\u{1F918}",
        "crossed_fingers": "\u{1F91E}", "writing_hand": "\u{270D}\u{FE0F}",

        // Hearts & Symbols
        "heart": "\u{2764}\u{FE0F}", "orange_heart": "\u{1F9E1}",
        "yellow_heart": "\u{1F49B}", "green_heart": "\u{1F49A}",
        "blue_heart": "\u{1F499}", "purple_heart": "\u{1F49C}",
        "black_heart": "\u{1F5A4}", "broken_heart": "\u{1F494}",
        "sparkling_heart": "\u{1F496}", "star": "\u{2B50}",
        "star2": "\u{1F31F}", "sparkles": "\u{2728}", "fire": "\u{1F525}",
        "boom": "\u{1F4A5}", "zap": "\u{26A1}", "snowflake": "\u{2744}\u{FE0F}",
        "rainbow": "\u{1F308}", "sun_with_face": "\u{1F31E}",

        // Objects & Tech
        "rocket": "\u{1F680}", "airplane": "\u{2708}\u{FE0F}",
        "tada": "\u{1F389}", "confetti_ball": "\u{1F38A}",
        "trophy": "\u{1F3C6}", "medal": "\u{1F3C5}",
        "bulb": "\u{1F4A1}", "flashlight": "\u{1F526}",
        "wrench": "\u{1F527}", "hammer": "\u{1F528}", "nut_and_bolt": "\u{1F529}",
        "gear": "\u{2699}\u{FE0F}", "link": "\u{1F517}",
        "lock": "\u{1F512}", "unlock": "\u{1F513}",
        "key": "\u{1F511}", "bell": "\u{1F514}",
        "loudspeaker": "\u{1F4E2}", "mega": "\u{1F4E3}",
        "package": "\u{1F4E6}", "email": "\u{1F4E7}",
        "inbox_tray": "\u{1F4E5}", "outbox_tray": "\u{1F4E4}",
        "bookmark": "\u{1F516}", "pushpin": "\u{1F4CC}",
        "paperclip": "\u{1F4CE}", "scissors": "\u{2702}\u{FE0F}",
        "pencil": "\u{270F}\u{FE0F}", "pencil2": "\u{270F}\u{FE0F}",
        "pen": "\u{1F58A}\u{FE0F}", "memo": "\u{1F4DD}",
        "clipboard": "\u{1F4CB}", "calendar": "\u{1F4C5}",
        "chart_with_upwards_trend": "\u{1F4C8}", "chart_with_downwards_trend": "\u{1F4C9}",
        "bar_chart": "\u{1F4CA}",
        "computer": "\u{1F4BB}", "keyboard": "\u{2328}\u{FE0F}",
        "desktop_computer": "\u{1F5A5}\u{FE0F}", "iphone": "\u{1F4F1}",
        "camera": "\u{1F4F7}", "video_camera": "\u{1F4F9}",
        "tv": "\u{1F4FA}", "battery": "\u{1F50B}",
        "electric_plug": "\u{1F50C}", "mag": "\u{1F50D}",

        // Documents & Files
        "file_folder": "\u{1F4C1}", "open_file_folder": "\u{1F4C2}",
        "page_facing_up": "\u{1F4C4}", "page_with_curl": "\u{1F4C3}",
        "bookmark_tabs": "\u{1F4D1}", "books": "\u{1F4DA}",
        "book": "\u{1F4D6}", "ledger": "\u{1F4D2}",
        "newspaper": "\u{1F4F0}",

        // Status & Indicators
        "white_check_mark": "\u{2705}", "heavy_check_mark": "\u{2714}\u{FE0F}",
        "ballot_box_with_check": "\u{2611}\u{FE0F}", "x": "\u{274C}",
        "heavy_multiplication_x": "\u{2716}\u{FE0F}",
        "exclamation": "\u{2757}", "question": "\u{2753}",
        "grey_exclamation": "\u{2755}", "grey_question": "\u{2754}",
        "warning": "\u{26A0}\u{FE0F}", "no_entry": "\u{26D4}",
        "no_entry_sign": "\u{1F6AB}", "stop_sign": "\u{1F6D1}",
        "construction": "\u{1F6A7}", "rotating_light": "\u{1F6A8}",
        "red_circle": "\u{1F534}", "orange_circle": "\u{1F7E0}",
        "yellow_circle": "\u{1F7E1}", "green_circle": "\u{1F7E2}",
        "blue_circle": "\u{1F535}", "purple_circle": "\u{1F7E3}",
        "white_circle": "\u{26AA}", "black_circle": "\u{26AB}",
        "large_blue_diamond": "\u{1F537}", "large_orange_diamond": "\u{1F536}",

        // Arrows
        "arrow_up": "\u{2B06}\u{FE0F}", "arrow_down": "\u{2B07}\u{FE0F}",
        "arrow_left": "\u{2B05}\u{FE0F}", "arrow_right": "\u{27A1}\u{FE0F}",
        "arrow_upper_right": "\u{2197}\u{FE0F}", "arrow_lower_right": "\u{2198}\u{FE0F}",
        "arrow_upper_left": "\u{2196}\u{FE0F}", "arrow_lower_left": "\u{2199}\u{FE0F}",
        "arrows_counterclockwise": "\u{1F504}", "leftwards_arrow_with_hook": "\u{21A9}\u{FE0F}",

        // Nature & Animals
        "dog": "\u{1F436}", "cat": "\u{1F431}", "mouse": "\u{1F42D}",
        "bear": "\u{1F43B}", "panda_face": "\u{1F43C}", "fox_face": "\u{1F98A}",
        "unicorn": "\u{1F984}", "bee": "\u{1F41D}", "bug": "\u{1F41B}",
        "spider": "\u{1F577}\u{FE0F}", "snake": "\u{1F40D}",
        "turtle": "\u{1F422}", "octopus": "\u{1F419}",
        "crab": "\u{1F980}", "whale": "\u{1F433}",
        "dolphin": "\u{1F42C}", "bird": "\u{1F426}",
        "eagle": "\u{1F985}", "butterfly": "\u{1F98B}",
        "seedling": "\u{1F331}", "evergreen_tree": "\u{1F332}",
        "deciduous_tree": "\u{1F333}", "palm_tree": "\u{1F334}",
        "cactus": "\u{1F335}", "herb": "\u{1F33F}",
        "four_leaf_clover": "\u{1F340}", "maple_leaf": "\u{1F341}",
        "fallen_leaf": "\u{1F342}", "mushroom": "\u{1F344}",
        "bouquet": "\u{1F490}", "rose": "\u{1F339}",
        "sunflower": "\u{1F33B}", "cherry_blossom": "\u{1F338}",

        // Food & Drink
        "apple": "\u{1F34E}", "coffee": "\u{2615}",
        "beer": "\u{1F37A}", "wine_glass": "\u{1F377}",
        "pizza": "\u{1F355}", "hamburger": "\u{1F354}",
        "cake": "\u{1F370}", "ice_cream": "\u{1F368}",
        "cookie": "\u{1F36A}", "chocolate_bar": "\u{1F36B}",
        "popcorn": "\u{1F37F}", "egg": "\u{1F95A}",

        // People & Activities
        "raised_hand": "\u{270B}",
        "runner": "\u{1F3C3}", "dancer": "\u{1F483}",
        "man_technologist": "\u{1F468}\u{200D}\u{1F4BB}",
        "woman_technologist": "\u{1F469}\u{200D}\u{1F4BB}",

        // Misc commonly used
        "100": "\u{1F4AF}", "currency_exchange": "\u{1F4B1}",
        "heavy_dollar_sign": "\u{1F4B2}", "moneybag": "\u{1F4B0}",
        "gem": "\u{1F48E}", "crown": "\u{1F451}",
        "ring": "\u{1F48D}", "gift": "\u{1F381}",
        "balloon": "\u{1F388}", "party_popper": "\u{1F389}",
        "hourglass": "\u{231B}", "stopwatch": "\u{23F1}\u{FE0F}",
        "timer_clock": "\u{23F2}\u{FE0F}", "alarm_clock": "\u{23F0}",
        "clock": "\u{1F570}\u{FE0F}", "world_map": "\u{1F5FA}\u{FE0F}",
        "globe_with_meridians": "\u{1F310}", "earth_americas": "\u{1F30E}",
        "earth_africa": "\u{1F30D}", "earth_asia": "\u{1F30F}",
        "label": "\u{1F3F7}\u{FE0F}", "shield": "\u{1F6E1}\u{FE0F}",
        "atom": "\u{269B}\u{FE0F}", "infinity": "\u{267E}\u{FE0F}",
        "recycle": "\u{267B}\u{FE0F}", "yin_yang": "\u{262F}\u{FE0F}",
        "peace": "\u{262E}\u{FE0F}", "copyright": "\u{00A9}\u{FE0F}",
        "registered": "\u{00AE}\u{FE0F}", "tm": "\u{2122}\u{FE0F}",
        "hash": "\u{0023}\u{FE0F}\u{20E3}", "information_source": "\u{2139}\u{FE0F}",
    ]
}
