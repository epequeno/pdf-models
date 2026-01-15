module Styles exposing (..)

import Css exposing (..)
import Css.Global
-- =============================================================================
-- DESIGN SYSTEM: NEXUS
-- Premium dark theme with electric cyan accents
-- Inspired by Linear/Stripe design language
-- =============================================================================


-- COLORS


colors =
    { -- Backgrounds (layered for depth)
      background = hex "0a0a0b"
    , surface = hex "141415"
    , surfaceRaised = hex "1c1c1e"
    , overlay = hex "252528"

    -- Text (proper hierarchy)
    , textPrimary = hex "f4f4f5"
    , textSecondary = hex "a1a1aa"
    , textTertiary = hex "71717a"
    , textInverse = hex "09090b"

    -- Accent - Electric Cyan (refined)
    , accent = hex "22d3ee"
    , accentHover = hex "06b6d4"
    , accentPressed = hex "0891b2"
    , accentMuted = rgba 34 211 238 0.1
    , accentSubtle = rgba 34 211 238 0.2

    -- Semantic
    , success = hex "4ade80"
    , successMuted = rgba 74 222 128 0.15
    , warning = hex "fbbf24"
    , warningMuted = rgba 251 191 36 0.15
    , error = hex "f87171"
    , errorMuted = rgba 248 113 113 0.15
    , info = hex "60a5fa"
    , infoMuted = rgba 96 165 250 0.15

    -- Borders
    , border = hex "27272a"
    , borderStrong = hex "3f3f46"
    , borderFocus = hex "22d3ee"

    -- Legacy aliases (for gradual migration)
    , hover = hex "252528"
    , active = hex "3f3f46"
    , focus = hex "22d3ee"
    , accentPrimary = hex "22d3ee"
    , accentSuccess = hex "4ade80"
    , accentWarning = hex "fbbf24"
    , accentError = hex "f87171"
    }



-- TYPOGRAPHY


fontStack : List String
fontStack =
    [ "Inter"
    , "-apple-system"
    , "BlinkMacSystemFont"
    , "Segoe UI"
    , "Roboto"
    , "Helvetica Neue"
    , "Arial"
    , "sans-serif"
    ]


codeFontStack : List String
codeFontStack =
    [ "JetBrains Mono"
    , "Fira Code"
    , "SF Mono"
    , "Consolas"
    , "Liberation Mono"
    , "monospace"
    ]


fontSize =
    { display = px 32
    , h1 = px 24
    , h2 = px 18
    , body = px 14
    , small = px 13
    , caption = px 12
    , code = px 13
    }


fontWeights =
    { normal = int 400
    , medium = int 500
    , semibold = int 600
    }


lineHeights =
    { tight = num 1.25
    , normal = num 1.5
    , relaxed = num 1.625
    }



-- SPACING (8px grid)


spacing =
    { none = px 0
    , xs = px 4
    , sm = px 8
    , md = px 12
    , base = px 16
    , lg = px 20
    , xl = px 24
    , xxl = px 32
    , xxxl = px 40
    , huge = px 48
    , massive = px 64
    }



-- BORDER RADIUS


radius =
    { none = px 0
    , sm = px 4
    , md = px 6
    , lg = px 8
    , xl = px 12
    , full = px 9999
    }



-- SHADOWS


shadows =
    { sm = Css.property "box-shadow" "0 1px 2px rgba(0, 0, 0, 0.3)"
    , md = Css.property "box-shadow" "0 4px 6px rgba(0, 0, 0, 0.3)"
    , lg = Css.property "box-shadow" "0 8px 16px rgba(0, 0, 0, 0.4)"
    , glow = Css.property "box-shadow" "0 0 20px rgba(34, 211, 238, 0.15)"
    , glowStrong = Css.property "box-shadow" "0 0 30px rgba(34, 211, 238, 0.25)"
    , inset = Css.property "box-shadow" "inset 0 1px 2px rgba(0, 0, 0, 0.2)"
    }



-- TRANSITIONS


transitions =
    { fast = Css.property "transition" "all 100ms ease"
    , base = Css.property "transition" "all 150ms ease"
    , slow = Css.property "transition" "all 200ms ease"
    , colors = Css.property "transition" "background-color 150ms ease, border-color 150ms ease, color 150ms ease"
    }



-- GLOBAL STYLES


globalStyles : List Css.Global.Snippet
globalStyles =
    [ Css.Global.html
        [ backgroundColor colors.background
        , color colors.textPrimary
        , fontFamilies fontStack
        , Css.fontSize fontSize.body
        , lineHeight lineHeights.normal
        , margin zero
        , padding zero
        , property "-webkit-font-smoothing" "antialiased"
        , property "-moz-osx-font-smoothing" "grayscale"
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
        [ color colors.accent
        , textDecoration none
        , cursor pointer
        , transitions.base
        , hover
            [ color colors.accentHover
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
    , Css.Global.selector "::selection"
        [ backgroundColor colors.accentSubtle
        , color colors.textPrimary
        ]
    ]



-- COMMON STYLES


containerStyle : Style
containerStyle =
    batch
        [ maxWidth (px 1200)
        , margin2 zero auto
        , padding2 spacing.xl spacing.xxl
        ]


narrowContainerStyle : Style
narrowContainerStyle =
    batch
        [ maxWidth (px 480)
        , margin2 zero auto
        , padding2 spacing.xl spacing.xxl
        ]


centeredBoxStyle : Style
centeredBoxStyle =
    batch
        [ maxWidth (px 420)
        , margin2 (vh 15) auto
        , padding spacing.xxl
        ]


cardStyle : Style
cardStyle =
    batch
        [ backgroundColor colors.surface
        , border3 (px 1) solid colors.border
        , borderRadius radius.md
        , padding spacing.xl
        ]


cardInteractiveStyle : Style
cardInteractiveStyle =
    batch
        [ cardStyle
        , cursor pointer
        , transitions.base
        , hover
            [ backgroundColor colors.surfaceRaised
            , borderColor colors.borderStrong
            ]
        ]



-- TEXT STYLES


textDisplay : Style
textDisplay =
    batch
        [ Css.fontSize fontSize.display
        , fontWeight fontWeights.semibold
        , lineHeight lineHeights.tight
        , color colors.textPrimary
        , letterSpacing (px -0.5)
        ]


textH1 : Style
textH1 =
    batch
        [ Css.fontSize fontSize.h1
        , fontWeight fontWeights.semibold
        , lineHeight lineHeights.tight
        , color colors.textPrimary
        ]


textH2 : Style
textH2 =
    batch
        [ Css.fontSize fontSize.h2
        , fontWeight fontWeights.medium
        , lineHeight lineHeights.tight
        , color colors.textPrimary
        ]


textBody : Style
textBody =
    batch
        [ Css.fontSize fontSize.body
        , fontWeight fontWeights.normal
        , lineHeight lineHeights.normal
        , color colors.textPrimary
        ]


textSecondary : Style
textSecondary =
    batch
        [ Css.fontSize fontSize.body
        , fontWeight fontWeights.normal
        , lineHeight lineHeights.normal
        , color colors.textSecondary
        ]


textSmall : Style
textSmall =
    batch
        [ Css.fontSize fontSize.small
        , fontWeight fontWeights.normal
        , lineHeight lineHeights.normal
        , color colors.textSecondary
        ]


textCaption : Style
textCaption =
    batch
        [ Css.fontSize fontSize.caption
        , fontWeight fontWeights.medium
        , lineHeight lineHeights.normal
        , color colors.textTertiary
        , textTransform uppercase
        , letterSpacing (px 0.5)
        ]


textCode : Style
textCode =
    batch
        [ fontFamilies codeFontStack
        , Css.fontSize fontSize.code
        , fontWeight fontWeights.normal
        , lineHeight lineHeights.normal
        , color colors.textSecondary
        ]



-- FOCUS STYLES


focusRing : Style
focusRing =
    batch
        [ outline none
        , property "box-shadow" "0 0 0 2px rgba(34, 211, 238, 0.4)"
        , borderColor colors.borderFocus
        ]



-- UTILITY STYLES


flexRow : Style
flexRow =
    batch
        [ displayFlex
        , flexDirection row
        , alignItems center
        ]


flexColumn : Style
flexColumn =
    batch
        [ displayFlex
        , flexDirection column
        ]


flexBetween : Style
flexBetween =
    batch
        [ displayFlex
        , justifyContent spaceBetween
        , alignItems center
        ]


gap : Css.Px -> Style
gap size =
    property "gap" (String.fromFloat size.numericValue ++ "px")
