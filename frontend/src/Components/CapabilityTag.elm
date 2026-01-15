module Components.CapabilityTag exposing (capabilityTag, capabilityTagWithLabel, capabilityIcon)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, title)
import Styles
import Types exposing (Capability(..), capabilityToIcon, capabilityToString)


{-| Render a capability as a small icon-only tag with tooltip
-}
capabilityTag : Capability -> Html msg
capabilityTag capability =
    span
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , Css.width (px 28)
            , Css.height (px 28)
            , backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.md
            , Css.fontSize (px 14)
            , color Styles.colors.textSecondary
            , Styles.transitions.fast
            , hover
                [ borderColor Styles.colors.borderStrong
                , color Styles.colors.textPrimary
                ]
            ]
        , title (capabilityToString capability)
        ]
        [ text (capabilityIcon capability) ]


{-| Render a capability with both icon and label
-}
capabilityTagWithLabel : Capability -> Html msg
capabilityTagWithLabel capability =
    span
        [ css
            [ displayFlex
            , alignItems center
            , Styles.gap Styles.spacing.xs
            , padding2 Styles.spacing.xs Styles.spacing.sm
            , backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.full
            , Css.fontSize Styles.fontSize.caption
            , color Styles.colors.textSecondary
            , Styles.transitions.fast
            , hover
                [ borderColor Styles.colors.borderStrong
                , color Styles.colors.textPrimary
                ]
            ]
        ]
        [ span [ css [ Css.fontSize (px 12) ] ] [ text (capabilityIcon capability) ]
        , text (capabilityToString capability)
        ]


{-| Get the icon character for a capability
Using simple text characters for now, can be replaced with SVG icons
-}
capabilityIcon : Capability -> String
capabilityIcon capability =
    case capability of
        Types.TableExtraction ->
            "▦"

        Types.FormulaMath ->
            "∑"

        Types.Handwriting ->
            "✎"

        Types.MultiColumn ->
            "▥"

        Types.MultiLanguage ->
            "🌐"

        Types.ImagePreservation ->
            "🖼"

        Types.StructuredOutput ->
            "{ }"

        Types.CustomPrompts ->
            "💬"
