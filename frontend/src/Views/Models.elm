module Views.Models exposing (view)

import Components.AppLayout as AppLayout
import Components.Badge as Badge
import Components.Button as Button
import Components.Icon as Icon
import Components.SearchInput as SearchInput
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Styles
import Types
    exposing
        ( Capability
        , Model
        , Msg(..)
        , PdfModel
        , Route(..)
        , allPdfModels
        , capabilityToString
        , categoryToString
        , modelMetadata
        , routeToPath
        )


view : Model -> Html Msg
view model =
    AppLayout.view
        { currentRoute = Models
        , userName = "John Doe"
        , userEmail = "john@example.com"
        , showUpgradeCard = True
        , isAdmin = False
        , onSignOut = SignOutClicked
        }
        [ viewModelsContent model
        ]


viewModelsContent : Model -> Html Msg
viewModelsContent model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "32px"
            , height (pct 100)
            , width (pct 100)
            ]
        ]
        [ -- Header section
          viewHeader

        -- Filter bar
        , viewFilterBar model

        -- Models grid
        , viewModelsGrid model
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent spaceBetween
            , width (pct 100)
            ]
        ]
        [ -- Left side: Breadcrumb, title, subtitle
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "4px"
                , flex (int 1)
                ]
            ]
            [ -- Breadcrumb
              div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 11)
                    , fontWeight (int 500)
                    , letterSpacing (px 0.5)
                    , color (hex "666666") -- $--foreground-subtle
                    ]
                ]
                [ text "Dashboard / Models" ]

            -- Title
            , div
                [ css
                    [ fontFamilies [ "Playfair Display", .value serif ]
                    , fontSize (px 36)
                    , fontWeight normal
                    , color (hex "FAF8F5") -- $--foreground
                    , marginTop (px 4)
                    ]
                ]
                [ text "Available Models" ]

            -- Subtitle
            , div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight normal
                    , color (hex "888888") -- $--foreground-muted
                    ]
                ]
                [ text "Explore and compare document processing models" ]
            ]

        -- Right side: Compare button
        , div
            [ css
                [ alignItems center
                , property "gap" "12px"
                ]
            ]
            [ Button.buttonDisabled Button.Secondary "Compare (0)"
            ]
        ]


viewFilterBar : Model -> Html Msg
viewFilterBar model =
    div
        [ css
            [ displayFlex
            , alignItems center
            , property "gap" "12px"
            , width (pct 100)
            ]
        ]
        [ -- Search input
          SearchInput.searchInput
            { placeholder = "Search models..."
            , value = model.modelSearchQuery
            , onInput = ModelSearchChanged
            }
            [ width (px 300) ]

        -- Spacer
        , div [ css [ flex (int 1) ] ] []

        -- Category filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Folder
            "Category: All"
            NoOp

        -- Capabilities filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Zap
            "Capabilities"
            NoOp

        -- Compute filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Cpu
            "Compute: All"
            NoOp
        ]


viewModelsGrid : Model -> Html Msg
viewModelsGrid model =
    let
        -- For now, just use all models. Filtering can be added later.
        models =
            allPdfModels
    in
    div
        [ css
            [ displayFlex
            , flexWrap wrap
            , property "gap" "24px"
            , width (pct 100)
            ]
        ]
        (List.map viewModelCard models)


viewModelCard : PdfModel -> Html Msg
viewModelCard pdfModel =
    let
        metadata =
            modelMetadata pdfModel

        -- Get first 3 capabilities as tags
        capabilityTags =
            List.take 3 metadata.capabilities
    in
    div
        [ css
            [ displayFlex
            , flexDirection column
            , width (px 340)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , overflow hidden
            , Styles.transitions.base
            , hover
                [ borderColor (hex "333333") -- Lighter border on hover
                ]
            ]
        ]
        [ -- Card header
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "12px"
                , padding (px 20)
                , width (pct 100)
                ]
            ]
            [ -- Top row: Model info and category badge
              div
                [ css
                    [ displayFlex
                    , justifyContent spaceBetween
                    , alignItems flexStart
                    , width (pct 100)
                    ]
                ]
                [ -- Model name and producer
                  div
                    [ css
                        [ displayFlex
                        , flexDirection column
                        , property "gap" "4px"
                        ]
                    ]
                    [ -- Model name
                      div
                        [ css
                            [ fontFamilies [ "Playfair Display", .value serif ]
                            , fontSize (px 20)
                            , fontWeight normal
                            , color (hex "FAF8F5") -- $--foreground
                            ]
                        ]
                        [ text (pdfModelDisplayName pdfModel) ]

                    -- Producer
                    , div
                        [ css
                            [ fontFamilies Styles.fontStack
                            , fontSize (px 12)
                            , fontWeight normal
                            , color (hex "666666") -- $--foreground-subtle
                            ]
                        ]
                        [ text metadata.producer ]
                    ]

                -- Category badge
                , Badge.badge Badge.Default (categoryToString metadata.category)
                ]

            -- Description
            , div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 13)
                    , fontWeight normal
                    , lineHeight (num 1.5)
                    , color (hex "888888") -- $--foreground-muted
                    , width (pct 100)
                    ]
                ]
                [ text (String.left 130 metadata.description ++ "...") ]

            -- Capability tags
            , div
                [ css
                    [ displayFlex
                    , property "gap" "6px"
                    , width (pct 100)
                    , flexWrap wrap
                    ]
                ]
                (List.map
                    (\cap -> Badge.badge Badge.Default (capabilityToString cap))
                    capabilityTags
                )
            ]

        -- Card footer
        , div
            [ css
                [ displayFlex
                , justifyContent spaceBetween
                , alignItems center
                , padding (px 20)
                , borderTop3 (px 1) solid (hex "151515") -- $--border-subtle
                , width (pct 100)
                ]
            ]
            [ -- Stats
              div
                [ css
                    [ displayFlex
                    , property "gap" "16px"
                    ]
                ]
                [ -- Accuracy stat
                  case metadata.benchmarks of
                    Just benchmarks ->
                        case benchmarks.accuracy of
                            Just accuracy ->
                                viewStat (String.fromFloat accuracy ++ "%") "Accuracy" True

                            Nothing ->
                                text ""

                    Nothing ->
                        text ""

                -- Speed stat
                , case metadata.benchmarks of
                    Just benchmarks ->
                        case benchmarks.speedTier of
                            Just speed ->
                                viewStat speed "Speed" False

                            Nothing ->
                                text ""

                    Nothing ->
                        text ""
                ]

            -- Try it button
            , a
                [ href (routeToPath (Upload pdfModel))
                , css
                    [ displayFlex
                    , alignItems center
                    , property "gap" "8px"
                    , padding2 (px 8) (px 16)
                    , backgroundColor (hex "C9A962") -- $--primary
                    , color (hex "0F0F0F") -- Dark text on gold background
                    , borderRadius (px 6)
                    , textDecoration none
                    , fontFamilies Styles.fontStack
                    , fontSize (px 12)
                    , fontWeight (int 500)
                    , border zero
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor (hex "D4B76E") -- Slightly lighter on hover
                        ]
                    ]
                ]
                [ text "Try it"
                , Icon.icon Icon.ArrowRightIcon Icon.Small (hex "0F0F0F")
                ]
            ]
        ]


viewStat : String -> String -> Bool -> Html Msg
viewStat value label isSuccess =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "2px"
            ]
        ]
        [ -- Value
          div
            [ css
                [ fontFamilies [ "JetBrains Mono", .value monospace ]
                , fontSize (px 14)
                , fontWeight (int 500)
                , color
                    (if isSuccess then
                        hex "4ADE80" -- $--success

                     else
                        hex "FAF8F5" -- $--foreground
                    )
                ]
            ]
            [ text value ]

        -- Label
        , div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 10)
                , fontWeight normal
                , color (hex "666666") -- $--foreground-subtle
                ]
            ]
            [ text label ]
        ]


-- HELPER FUNCTIONS


pdfModelDisplayName : PdfModel -> String
pdfModelDisplayName pdfModel =
    case pdfModel of
        Types.Marker ->
            "Marker"

        Types.Dolphin ->
            "Dolphin"

        Types.Docling ->
            "Docling"

        Types.DeepSeekOcr ->
            "DeepSeek OCR"

        Types.MinerU ->
            "MinerU"

        Types.OlmOcr ->
            "olmocr"

        Types.Docext ->
            "docext"

        Types.DotsOcr ->
            "dots.ocr"

        Types.LightOnOcr ->
            "LightOnOCR-2"

        Types.PaddleOcr ->
            "PaddleOCR"
