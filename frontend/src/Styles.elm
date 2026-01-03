module Styles exposing (..)

import Css exposing (..)
import Css.Global


-- COLORS


colors =
    { background = hex "1a1a1a"
    , surface = hex "252525"
    , border = hex "333333"
    , textPrimary = hex "e0e0e0"
    , textSecondary = hex "999999"
    , textTertiary = hex "666666"
    , accentPrimary = hex "00d9ff"
    , accentSuccess = hex "50fa7b"
    , accentWarning = hex "f1fa8c"
    , accentError = hex "ff5555"
    , hover = hex "2a2a2a"
    , active = hex "333333"
    , focus = hex "00d9ff"
    }



-- TYPOGRAPHY


fontStack : List String
fontStack =
    [ "JetBrains Mono"
    , "Fira Code"
    , "SF Mono"
    , "Consolas"
    , "Liberation Mono"
    , "monospace"
    ]


fontSize =
    { h1 = px 24
    , h2 = px 18
    , body = px 14
    , small = px 12
    , code = px 13
    }


fontWeight =
    { normal = int 400
    , semibold = int 600
    }



-- SPACING


spacing =
    { xs = px 4
    , sm = px 8
    , md = px 16
    , lg = px 24
    , xl = px 32
    , xxl = px 48
    }



-- GLOBAL STYLES


globalStyles : List Css.Global.Snippet
globalStyles =
    [ Css.Global.html
        [ backgroundColor colors.background
        , color colors.textPrimary
        , fontFamilies fontStack
        , Css.fontSize fontSize.body
        , lineHeight (num 1.5)
        , margin zero
        , padding zero
        ]
    , Css.Global.body
        [ margin zero
        , padding zero
        , minHeight (vh 100)
        ]
    , Css.Global.everything
        [ boxSizing borderBox
        ]
    , Css.Global.a
        [ color colors.accentPrimary
        , textDecoration none
        , cursor pointer
        , hover
            [ textDecoration underline
            ]
        ]
    , Css.Global.button
        [ fontFamilies fontStack
        , Css.fontSize fontSize.body
        , cursor pointer
        ]
    , Css.Global.input
        [ fontFamilies fontStack
        , Css.fontSize fontSize.body
        ]
    ]



-- COMMON STYLES


containerStyle : Style
containerStyle =
    batch
        [ maxWidth (px 1200)
        , margin2 zero auto
        , padding spacing.lg
        ]


centeredBoxStyle : Style
centeredBoxStyle =
    batch
        [ maxWidth (px 400)
        , margin2 (vh 20) auto
        , padding spacing.xl
        ]


cardStyle : Style
cardStyle =
    batch
        [ backgroundColor colors.surface
        , border3 (px 1) solid colors.border
        , padding spacing.lg
        ]
