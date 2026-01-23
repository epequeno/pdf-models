module Styles exposing (..)

import Css exposing (..)
import Css.Global



-- =============================================================================
-- DESIGN SYSTEM: FROM PENCIL DESIGN
-- Premium dark theme with warm gold/bronze accents
-- Matches /Users/steven/Documents/pdf-models design
-- =============================================================================
-- COLORS


colors =
    { -- Backgrounds
      background = hex "0F0F0F"
    , backgroundSidebar = hex "0A0A0A"
    , surface = hex "0F0F0F"
    , surfaceRaised = hex "1c1c1e"
    , overlay = hex "252528"
    , card = hex "0F0F0F"

    -- Text (foreground)
    , textPrimary = hex "FAF8F5"
    , foreground = hex "FAF8F5"
    , foregroundMuted = hex "888888"
    , foregroundSubtle = hex "666666"
    , textSecondary = hex "888888"
    , textTertiary = hex "666666"
    , textInverse = hex "0A0A0A"

    -- Primary - Warm Gold/Bronze
    , primary = hex "C9A962"
    , primaryForeground = hex "0A0A0A"
    , accent = hex "C9A962"
    , accentHover = hex "D4B976"
    , accentPressed = hex "B89954"
    , accentMuted = rgba 201 169 98 0.1
    , accentSubtle = rgba 201 169 98 0.2

    -- Active state background
    , activeBg = rgba 201 169 98 0.063

    -- Semantic colors
    , success = hex "4ADE80"
    , successMuted = rgba 74 222 128 0.25
    , warning = hex "FBBF24"
    , warningMuted = rgba 251 191 36 0.25
    , error = hex "EF4444"
    , errorMuted = rgba 239 68 68 0.25
    , info = hex "60A5FA"
    , infoMuted = rgba 96 165 250 0.25

    -- Borders (gold tinted with varying opacity)
    , border = rgba 201 169 98 0.125
    , borderButton = rgba 201 169 98 0.145
    , borderEmphasis = rgba 201 169 98 0.188
    , borderSubtle = rgba 201 169 98 0.082
    , borderStrong = rgba 201 169 98 0.188
    , borderFocus = hex "C9A962"

    -- Legacy aliases (for gradual migration)
    , hover = hex "252528"
    , active = rgba 201 169 98 0.188
    , focus = hex "C9A962"
    , accentPrimary = hex "C9A962"
    , accentSuccess = hex "4ADE80"
    , accentWarning = hex "FBBF24"
    , accentError = hex "EF4444"
    }



-- TYPOGRAPHY


fontStack : List String
fontStack =
    [ "Manrope"
    , "-apple-system"
    , "BlinkMacSystemFont"
    , "Segoe UI"
    , "Roboto"
    , "Helvetica Neue"
    , "Arial"
    , "sans-serif"
    ]


displayFontStack : List String
displayFontStack =
    [ "Playfair Display"
    , "Georgia"
    , "Times New Roman"
    , "serif"
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
        , fontFamilies displayFontStack
        , fontWeight fontWeights.normal
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



-- GRID UTILITIES


gridColumns : Int -> Style
gridColumns cols =
    property "grid-template-columns" ("repeat(" ++ String.fromInt cols ++ ", minmax(0, 1fr))")


modelCardGrid : Style
modelCardGrid =
    batch
        [ property "display" "grid"
        , property "grid-template-columns" "repeat(auto-fill, minmax(280px, 1fr))"
        , gap spacing.lg
        ]


modelCardGridCompact : Style
modelCardGridCompact =
    batch
        [ property "display" "grid"
        , property "grid-template-columns" "repeat(2, 1fr)"
        , gap spacing.md
        ]



-- MODEL CARD STYLES


modelCardStyle : Style
modelCardStyle =
    batch
        [ backgroundColor colors.surface
        , border3 (px 1) solid colors.border
        , borderRadius radius.lg
        , padding spacing.lg
        , cursor pointer
        , transitions.base
        , hover
            [ backgroundColor colors.surfaceRaised
            , borderColor colors.borderStrong
            , transform (translateY (px -2))
            , shadows.md
            ]
        ]


modelCardSelectedStyle : Style
modelCardSelectedStyle =
    batch
        [ modelCardStyle
        , borderColor colors.accent
        , shadows.glow
        , hover
            [ borderColor colors.accent
            , shadows.glowStrong
            ]
        ]


modelCardExpandedStyle : Style
modelCardExpandedStyle =
    batch
        [ modelCardStyle
        , property "grid-column" "1 / -1"
        ]



-- CATEGORY COLORS


categoryColor : String -> Color
categoryColor category =
    case category of
        "OCR & Conversion" ->
            colors.accent

        "Layout Analysis" ->
            colors.info

        "Document Understanding" ->
            colors.success

        _ ->
            colors.textSecondary


categoryBgColor : String -> Color
categoryBgColor category =
    case category of
        "OCR & Conversion" ->
            colors.accentMuted

        "Layout Analysis" ->
            colors.infoMuted

        "Document Understanding" ->
            colors.successMuted

        _ ->
            colors.surface



-- PILL/BADGE STYLES


pillStyle : Style
pillStyle =
    batch
        [ displayFlex
        , alignItems center
        , padding2 spacing.xs spacing.sm
        , borderRadius radius.full
        , Css.fontSize fontSize.caption
        , fontWeight fontWeights.medium
        ]


categoryPillStyle : String -> Style
categoryPillStyle category =
    batch
        [ pillStyle
        , backgroundColor (categoryBgColor category)
        , color (categoryColor category)
        ]



-- MODAL/OVERLAY STYLES


modalOverlay : Style
modalOverlay =
    batch
        [ position fixed
        , top zero
        , left zero
        , right zero
        , bottom zero
        , backgroundColor (rgba 0 0 0 0.7)
        , displayFlex
        , alignItems center
        , justifyContent center
        , property "z-index" "1000"
        , property "backdrop-filter" "blur(4px)"
        ]


modalContent : Style
modalContent =
    batch
        [ backgroundColor colors.surfaceRaised
        , border3 (px 1) solid colors.border
        , borderRadius radius.xl
        , shadows.lg
        , maxWidth (px 560)
        , Css.width (pct 90)
        , maxHeight (vh 70)
        , overflow hidden
        , displayFlex
        , flexDirection column
        ]



-- SCROLLBAR STYLES


customScrollbar : Style
customScrollbar =
    batch
        [ property "scrollbar-width" "thin"
        , property "scrollbar-color" (colorToString colors.borderStrong ++ " transparent")
        ]


colorToString : Color -> String
colorToString color =
    -- Convert Color to string for CSS properties
    color.value
