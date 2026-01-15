module Components.ModelCard exposing (modelCard, modelCardCompact, modelCardExpanded)

import Components.CapabilityTag exposing (capabilityIcon, capabilityTag)
import Components.PerformanceIndicator exposing (benchmarkDisplay, performanceIndicator, performanceIndicatorCompact)
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href)
import Html.Styled.Events exposing (onClick, onMouseEnter, onMouseLeave, stopPropagationOn)
import Json.Decode as Decode
import Styles
import Types
    exposing
        ( Capability
        , ComputeType(..)
        , ModelMetadata
        , PdfModel
        , categoryToString
        , capabilityToString
        , computeTypeToString
        , modelMetadata
        , outputFormatToString
        , pdfModelToDisplayName
        )


{-| Standard model card for the upload page grid
-}
modelCard :
    { model : PdfModel
    , isSelected : Bool
    , isHovered : Bool
    , onSelect : PdfModel -> msg
    , onHover : Maybe PdfModel -> msg
    }
    -> Html msg
modelCard config =
    let
        metadata =
            modelMetadata config.model

        cardStyle =
            if config.isSelected then
                Styles.modelCardSelectedStyle

            else
                Styles.modelCardStyle
    in
    div
        [ css [ cardStyle ]
        , onClick (config.onSelect config.model)
        , onMouseEnter (config.onHover (Just config.model))
        , onMouseLeave (config.onHover Nothing)
        ]
        [ -- Header with name and selection indicator
          div
            [ css
                [ Styles.flexBetween
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ div
                [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm ] ]
                [ if config.isSelected then
                    span
                        [ css
                            [ color Styles.colors.accent
                            , Css.fontSize (px 16)
                            ]
                        ]
                        [ text "✓" ]

                  else
                    text ""
                , span
                    [ css
                        [ fontWeight Styles.fontWeights.semibold
                        , color Styles.colors.textPrimary
                        , Css.fontSize Styles.fontSize.body
                        ]
                    ]
                    [ text (modelName config.model) ]
                ]
            , performanceIndicatorCompact metadata.performanceTier
            ]

        -- Producer
        , div
            [ css
                [ Css.fontSize Styles.fontSize.small
                , color Styles.colors.textTertiary
                , marginBottom Styles.spacing.md
                ]
            ]
            [ text metadata.producer ]

        -- Category pill and compute type
        , div
            [ css [ marginBottom Styles.spacing.md, Styles.flexRow, Styles.gap Styles.spacing.sm ] ]
            [ span
                [ css [ Styles.categoryPillStyle (categoryToString metadata.category) ] ]
                [ text (categoryToString metadata.category) ]
            , computeTypeBadge metadata.computeType
            ]

        -- Capabilities row
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.xs
                , flexWrap wrap
                ]
            ]
            (List.take 4 metadata.capabilities |> List.map capabilityTag)
        ]


{-| Compact model card for smaller contexts
-}
modelCardCompact :
    { model : PdfModel
    , isSelected : Bool
    , onSelect : PdfModel -> msg
    }
    -> Html msg
modelCardCompact config =
    let
        metadata =
            modelMetadata config.model

        cardStyle =
            batch
                [ backgroundColor Styles.colors.surface
                , border3 (px 1) solid
                    (if config.isSelected then
                        Styles.colors.accent

                     else
                        Styles.colors.border
                    )
                , borderRadius Styles.radius.md
                , padding Styles.spacing.md
                , cursor pointer
                , Styles.transitions.fast
                , hover
                    [ borderColor Styles.colors.borderStrong
                    ]
                , if config.isSelected then
                    Styles.shadows.glow

                  else
                    batch []
                ]
    in
    div
        [ css [ cardStyle ]
        , onClick (config.onSelect config.model)
        ]
        [ div
            [ css [ Styles.flexBetween ] ]
            [ span
                [ css
                    [ fontWeight Styles.fontWeights.medium
                    , color Styles.colors.textPrimary
                    , Css.fontSize Styles.fontSize.small
                    ]
                ]
                [ text (modelName config.model) ]
            , if config.isSelected then
                span [ css [ color Styles.colors.accent ] ] [ text "✓" ]

              else
                text ""
            ]
        , span
            [ css
                [ Css.fontSize Styles.fontSize.caption
                , color Styles.colors.textTertiary
                ]
            ]
            [ text metadata.producer ]
        ]


{-| Expanded model card with full details (for Models page)
-}
modelCardExpanded :
    { model : PdfModel
    , isSelected : Bool
    , isExpanded : Bool
    , onSelect : PdfModel -> msg
    , onToggleExpand : PdfModel -> msg
    , onToggleComparison : PdfModel -> msg
    , isInComparison : Bool
    }
    -> Html msg
modelCardExpanded config =
    let
        metadata =
            modelMetadata config.model
    in
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid
                (if config.isSelected then
                    Styles.colors.accent

                 else
                    Styles.colors.border
                )
            , borderRadius Styles.radius.lg
            , overflow hidden
            , Styles.transitions.base
            , if config.isSelected then
                Styles.shadows.glow

              else
                batch []
            ]
        ]
        [ -- Clickable header
          div
            [ css
                [ padding Styles.spacing.lg
                , cursor pointer
                , Styles.transitions.fast
                , hover [ backgroundColor Styles.colors.surfaceRaised ]
                ]
            , onClick (config.onToggleExpand config.model)
            ]
            [ -- Top row
              div
                [ css [ Styles.flexBetween, marginBottom Styles.spacing.sm ] ]
                [ div [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm ] ]
                    [ -- Expand indicator
                      span
                        [ css
                            [ color Styles.colors.textTertiary
                            , Styles.transitions.fast
                            , transform
                                (if config.isExpanded then
                                    rotate (deg 90)

                                 else
                                    rotate (deg 0)
                                )
                            ]
                        ]
                        [ text "▶" ]

                    -- Model name
                    , span
                        [ css
                            [ fontWeight Styles.fontWeights.semibold
                            , color Styles.colors.textPrimary
                            , Css.fontSize Styles.fontSize.h2
                            ]
                        ]
                        [ text (modelName config.model) ]
                    ]

                -- Right side: performance + comparison checkbox
                , div [ css [ Styles.flexRow, Styles.gap Styles.spacing.md ] ]
                    [ performanceIndicator metadata.performanceTier
                    , comparisonCheckbox config.isInComparison config.onToggleComparison config.model
                    ]
                ]

            -- Producer, category, and compute type
            , div
                [ css [ Styles.flexRow, Styles.gap Styles.spacing.md, marginBottom Styles.spacing.sm ] ]
                [ span
                    [ css [ Css.fontSize Styles.fontSize.small, color Styles.colors.textSecondary ] ]
                    [ text ("by " ++ metadata.producer) ]
                , span
                    [ css [ Styles.categoryPillStyle (categoryToString metadata.category) ] ]
                    [ text (categoryToString metadata.category) ]
                , computeTypeBadge metadata.computeType
                ]

            -- Short description
            , p
                [ css
                    [ Css.fontSize Styles.fontSize.small
                    , color Styles.colors.textSecondary
                    , lineHeight Styles.lineHeights.relaxed
                    , margin zero
                    ]
                ]
                [ text (truncateDescription metadata.description) ]
            ]

        -- Expanded content
        , if config.isExpanded then
            expandedContent metadata config.onSelect config.model

          else
            text ""
        ]


expandedContent : ModelMetadata -> (PdfModel -> msg) -> PdfModel -> Html msg
expandedContent metadata onSelect model =
    div
        [ css
            [ padding Styles.spacing.lg
            , paddingTop zero
            , borderTop3 (px 1) solid Styles.colors.border
            , marginTop Styles.spacing.sm
            , paddingTop Styles.spacing.lg
            ]
        ]
        [ -- Full description
          div [ css [ marginBottom Styles.spacing.lg ] ]
            [ h4
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    , marginTop zero
                    ]
                ]
                [ text "ABOUT" ]
            , p
                [ css
                    [ Css.fontSize Styles.fontSize.body
                    , color Styles.colors.textSecondary
                    , lineHeight Styles.lineHeights.relaxed
                    , margin zero
                    ]
                ]
                [ text metadata.description ]
            ]

        -- Capabilities
        , div [ css [ marginBottom Styles.spacing.lg ] ]
            [ h4
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    , marginTop zero
                    ]
                ]
                [ text "CAPABILITIES" ]
            , div
                [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm, flexWrap wrap ] ]
                (List.map capabilityTagFull metadata.capabilities)
            ]

        -- Benchmarks
        , div [ css [ marginBottom Styles.spacing.lg ] ]
            [ h4
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    , marginTop zero
                    ]
                ]
                [ text "PERFORMANCE" ]
            , benchmarkDisplay metadata.benchmarks
            ]

        -- Best for
        , div [ css [ marginBottom Styles.spacing.lg ] ]
            [ h4
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    , marginTop zero
                    ]
                ]
                [ text "BEST FOR" ]
            , div
                [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm, flexWrap wrap ] ]
                (List.map useCaseTag metadata.bestFor)
            ]

        -- Output format and links
        , div [ css [ Styles.flexBetween, alignItems flexEnd ] ]
            [ div [ css [ Styles.flexRow, Styles.gap Styles.spacing.lg ] ]
                [ -- Output format
                  div []
                    [ span
                        [ css [ Styles.textCaption, marginRight Styles.spacing.sm ] ]
                        [ text "OUTPUT:" ]
                    , span
                        [ css
                            [ fontFamilies Styles.codeFontStack
                            , Css.fontSize Styles.fontSize.small
                            , color Styles.colors.textSecondary
                            ]
                        ]
                        [ text (outputFormatToString metadata.outputFormat) ]
                    ]

                -- Links
                , div [ css [ Styles.flexRow, Styles.gap Styles.spacing.md ] ]
                    (List.filterMap identity
                        [ metadata.githubUrl |> Maybe.map (externalLink "GitHub")
                        , metadata.huggingFaceUrl |> Maybe.map (externalLink "HuggingFace")
                        , metadata.docsUrl |> Maybe.map (externalLink "Docs")
                        , metadata.arxivUrl |> Maybe.map (externalLink "arXiv")
                        ]
                    )
                ]

            -- Select button
            , button
                [ css
                    [ backgroundColor Styles.colors.accent
                    , color Styles.colors.textInverse
                    , border zero
                    , borderRadius Styles.radius.md
                    , padding2 Styles.spacing.sm Styles.spacing.lg
                    , fontWeight Styles.fontWeights.medium
                    , cursor pointer
                    , Styles.transitions.fast
                    , hover [ backgroundColor Styles.colors.accentHover ]
                    ]
                , onClick (onSelect model)
                ]
                [ text "Use This Model" ]
            ]
        ]


capabilityTagFull : Capability -> Html msg
capabilityTagFull capability =
    span
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.xs
            , padding2 Styles.spacing.xs Styles.spacing.sm
            , backgroundColor Styles.colors.surfaceRaised
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.full
            , Css.fontSize Styles.fontSize.caption
            , color Styles.colors.textSecondary
            ]
        ]
        [ span [] [ text (capabilityIcon capability) ]
        , text (capabilityToString capability)
        ]


useCaseTag : String -> Html msg
useCaseTag useCase =
    span
        [ css
            [ padding2 Styles.spacing.xs Styles.spacing.sm
            , backgroundColor Styles.colors.accentMuted
            , borderRadius Styles.radius.full
            , Css.fontSize Styles.fontSize.caption
            , color Styles.colors.accent
            ]
        ]
        [ text useCase ]


externalLink : String -> String -> Html msg
externalLink label url =
    a
        [ href url
        , Attr.target "_blank"
        , css
            [ Css.fontSize Styles.fontSize.small
            , color Styles.colors.accent
            , textDecoration none
            , Styles.transitions.fast
            , hover [ textDecoration underline ]
            ]
        ]
        [ text label ]


comparisonCheckbox : Bool -> (PdfModel -> msg) -> PdfModel -> Html msg
comparisonCheckbox isChecked onToggle model =
    div
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.xs
            , padding2 Styles.spacing.xs Styles.spacing.sm
            , backgroundColor
                (if isChecked then
                    Styles.colors.accentMuted

                 else
                    Styles.colors.surface
                )
            , border3 (px 1) solid
                (if isChecked then
                    Styles.colors.accent

                 else
                    Styles.colors.border
                )
            , borderRadius Styles.radius.md
            , cursor pointer
            , Styles.transitions.fast
            , hover [ borderColor Styles.colors.borderStrong ]
            ]
        , stopPropagationOn "click" (Decode.succeed ( onToggle model, True ))
        ]
        [ span
            [ css
                [ Css.fontSize (px 12)
                , color
                    (if isChecked then
                        Styles.colors.accent

                     else
                        Styles.colors.textTertiary
                    )
                ]
            ]
            [ text
                (if isChecked then
                    "✓"

                 else
                    "○"
                )
            ]
        , span
            [ css
                [ Css.fontSize Styles.fontSize.caption
                , color
                    (if isChecked then
                        Styles.colors.accent

                     else
                        Styles.colors.textTertiary
                    )
                ]
            ]
            [ text "Compare" ]
        ]


modelName : PdfModel -> String
modelName model =
    -- Extract just the model name without the description in parens
    let
        fullName =
            pdfModelToDisplayName model
    in
    case String.split " (" fullName of
        name :: _ ->
            name

        _ ->
            fullName


truncateDescription : String -> String
truncateDescription description =
    if String.length description > 120 then
        String.left 117 description ++ "..."

    else
        description


computeTypeBadge : ComputeType -> Html msg
computeTypeBadge computeType =
    let
        ( icon, bgColor, textColor ) =
            case computeType of
                CpuCompute ->
                    ( "⚙", Styles.colors.surface, Styles.colors.textSecondary )

                GpuCompute ->
                    ( "⚡", Styles.colors.warningMuted, Styles.colors.warning )
    in
    span
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.xs
            , padding2 Styles.spacing.xs Styles.spacing.sm
            , backgroundColor bgColor
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.full
            , Css.fontSize Styles.fontSize.caption
            , color textColor
            ]
        , Attr.title (computeTypeToString computeType)
        ]
        [ text icon
        , text (computeTypeToString computeType)
        ]
