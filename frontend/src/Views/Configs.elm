module Views.Configs exposing (view)

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
        ( ApprovalStatus(..)
        , Configuration
        , Model
        , Msg(..)
        , PdfModel
        , Route(..)
        , Visibility(..)
        , pdfModelToDisplayName
        , routeToPath
        )


view : Model -> Html Msg
view model =
    AppLayout.view
        { currentRoute = Configs
        , userName = "John Doe"
        , userEmail = "john@example.com"
        , showUpgradeCard = True
        , isAdmin = False
        , onSignOut = SignOutClicked
        }
        [ viewConfigsContent model
        ]


viewConfigsContent : Model -> Html Msg
viewConfigsContent model =
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

        -- Configurations table or empty state
        , if List.isEmpty model.configs.configurations && not model.configs.loading then
            viewEmptyState
          else
            viewConfigsTable model
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
                [ text "Dashboard / Configurations" ]

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
                [ text "My Configurations" ]

            -- Subtitle
            , div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight normal
                    , color (hex "888888") -- $--foreground-muted
                    ]
                ]
                [ text "Create and manage custom model configurations" ]
            ]

        -- Right side: Create button
        , div
            [ css
                [ alignItems center
                , property "gap" "12px"
                ]
            ]
            [ a
                [ href "#create"
                , onClick (ShowCreateConfigForm Types.Docling)
                , css
                    [ displayFlex
                    , alignItems center
                    , property "gap" "8px"
                    , padding2 (px 10) (px 16)
                    , backgroundColor (hex "C9A962") -- $--primary
                    , color (hex "0F0F0F") -- Dark text on gold background
                    , borderRadius (px 8)
                    , textDecoration none
                    , fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight (int 500)
                    , border zero
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor (hex "D4B76E") -- Slightly lighter on hover
                        ]
                    ]
                ]
                [ Icon.icon Icon.Plus Icon.Medium (hex "0F0F0F")
                , text "Create Configuration"
                ]
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
            { placeholder = "Search configurations..."
            , value = model.configs.searchQuery
            , onInput = ConfigSearchChanged
            }
            [ width (px 300) ]

        -- Spacer
        , div [ css [ flex (int 1) ] ] []

        -- Model filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Layers
            "Model: All"
            NoOp

        -- Visibility filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Eye
            "Visibility: All"
            NoOp

        -- Status filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.CheckCircle
            "Status: All"
            NoOp
        ]


viewConfigsTable : Model -> Html Msg
viewConfigsTable model =
    div
        [ css
            [ width (pct 100)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , overflow hidden
            ]
        ]
        [ -- Table header
          div
            [ css
                [ displayFlex
                , alignItems center
                , width (pct 100)
                , borderBottom3 (px 1) solid (hex "333333") -- $--border-emphasis
                ]
            ]
            [ tableHeaderCell "NAME" 0 -- flex: 1
            , tableHeaderCell "MODEL" 140
            , tableHeaderCell "VISIBILITY" 100
            , tableHeaderCell "STATUS" 110
            , tableHeaderCell "USAGE" 80
            , tableHeaderCell "ACTIONS" 120
            ]

        -- Table rows
        , div []
            (if model.configs.loading then
                [ viewLoadingRow ]
             else
                List.map viewConfigRow model.configs.configurations
            )
        ]


tableHeaderCell : String -> Int -> Html Msg
tableHeaderCell label width =
    div
        [ css
            [ displayFlex
            , alignItems center
            , padding2 (px 14) (px 20)
            , fontFamilies Styles.fontStack
            , fontSize (px 11)
            , fontWeight (int 600)
            , color (hex "C9A962") -- $--primary
            , if width > 0 then
                Css.width (px (toFloat width))
              else
                flex (int 1)
            ]
        ]
        [ text label ]


viewConfigRow : Configuration -> Html Msg
viewConfigRow config =
    div
        [ css
            [ displayFlex
            , alignItems center
            , width (pct 100)
            , borderBottom3 (px 1) solid (hex "151515") -- $--border-subtle
            , Styles.transitions.base
            , hover
                [ backgroundColor (rgba 201 169 98 0.063) -- $--active-bg
                ]
            ]
        ]
        [ -- Name and description
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "2px"
                , padding2 (px 16) (px 20)
                , flex (int 1)
                ]
            ]
            [ -- Name
              div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 13)
                    , fontWeight (int 500)
                    , color (hex "FAF8F5") -- $--foreground
                    ]
                ]
                [ text config.name ]

            -- Description
            , case config.description of
                Just desc ->
                    div
                        [ css
                            [ fontFamilies Styles.fontStack
                            , fontSize (px 11)
                            , fontWeight normal
                            , color (hex "666666") -- $--foreground-subtle
                            ]
                        ]
                        [ text (truncateText 40 desc) ]

                Nothing ->
                    text ""
            ]

        -- Model
        , tableCell (pdfModelShortName config.model) 140 ["Manrope", "sans-serif"] 13 (hex "888888")

        -- Visibility badge
        , div
            [ css
                [ displayFlex
                , alignItems center
                , padding2 (px 16) (px 20)
                , Css.width (px 100)
                ]
            ]
            [ viewVisibilityBadge config.visibility ]

        -- Status badge
        , div
            [ css
                [ displayFlex
                , alignItems center
                , padding2 (px 16) (px 20)
                , Css.width (px 110)
                ]
            ]
            [ viewStatusBadge config.approvalStatus ]

        -- Usage count
        , tableCell "0" 80 ["JetBrains Mono", "monospace"] 13 (hex "FAF8F5")

        -- Actions
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "8px"
                , padding2 (px 16) (px 20)
                , Css.width (px 120)
                ]
            ]
            [ -- Edit action
              button
                [ onClick (EditConfig config)
                , css
                    [ backgroundColor transparent
                    , border zero
                    , padding zero
                    , cursor pointer
                    , display inlineBlock
                    , Styles.transitions.base
                    , hover
                        [ property "transform" "scale(1.1)"
                        ]
                    ]
                ]
                [ Icon.icon Icon.Pencil Icon.Medium (hex "666666") ]

            -- Use action (select for upload)
            , button
                [ onClick (SelectConfigForUpload (Just config))
                , css
                    [ backgroundColor transparent
                    , border zero
                    , padding zero
                    , cursor pointer
                    , display inlineBlock
                    , Styles.transitions.base
                    , hover
                        [ property "transform" "scale(1.1)"
                        ]
                    ]
                ]
                [ Icon.icon Icon.Play Icon.Medium (hex "666666") ]

            -- Delete action
            , button
                [ onClick (ConfirmDeleteConfig config.configId)
                , css
                    [ backgroundColor transparent
                    , border zero
                    , padding zero
                    , cursor pointer
                    , display inlineBlock
                    , Styles.transitions.base
                    , hover
                        [ property "transform" "scale(1.1)"
                        ]
                    ]
                ]
                [ Icon.icon Icon.Trash2 Icon.Medium (hex "666666") ]
            ]
        ]


tableCell : String -> Int -> List String -> Float -> Color -> Html Msg
tableCell content width fontStack fontSize textColor =
    div
        [ css
            [ displayFlex
            , alignItems center
            , padding2 (px 16) (px 20)
            , fontFamilies (List.map (\f -> qt f) fontStack)
            , Css.fontSize (px fontSize)
            , fontWeight normal
            , color textColor
            , if width > 0 then
                Css.width (px (toFloat width))
              else
                flex (int 1)
            ]
        ]
        [ text content ]


viewVisibilityBadge : Visibility -> Html Msg
viewVisibilityBadge visibility =
    case visibility of
        Private ->
            Badge.badge Badge.Default "Private"

        Public ->
            Badge.badge Badge.Info "Public"


viewStatusBadge : ApprovalStatus -> Html Msg
viewStatusBadge status =
    case status of
        Approved ->
            Badge.badge Badge.Success "Active"

        PendingApproval ->
            Badge.badge Badge.Warning "Pending"

        Rejected ->
            Badge.badge Badge.Error "Rejected"


viewLoadingRow : Html Msg
viewLoadingRow =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , padding (px 40)
            , fontFamilies Styles.fontStack
            , fontSize (px 14)
            , color (hex "888888")
            ]
        ]
        [ text "Loading configurations..." ]


viewEmptyState : Html Msg
viewEmptyState =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , padding (px 60)
            , backgroundColor (hex "0A0A0A") -- $--background-sidebar
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            ]
        ]
        [ div
            [ css
                [ fontSize (px 48)
                , marginBottom (px 16)
                , opacity (num 0.3)
                ]
            ]
            [ text "⚙️" ]
        , h3
            [ css
                [ fontFamilies [ "Playfair Display", .value serif ]
                , fontSize (px 24)
                , fontWeight normal
                , color (hex "FAF8F5")
                , margin zero
                , marginBottom (px 8)
                ]
            ]
            [ text "No configurations yet" ]
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , color (hex "888888")
                , margin zero
                , marginBottom (px 16)
                ]
            ]
            [ text "Create your first custom model configuration" ]
        , a
            [ href "#create"
            , onClick (ShowCreateConfigForm Types.Docling)
            , css
                [ displayFlex
                , alignItems center
                , property "gap" "8px"
                , padding2 (px 10) (px 16)
                , backgroundColor (hex "C9A962") -- $--primary
                , color (hex "0F0F0F") -- Dark text on gold background
                , borderRadius (px 8)
                , textDecoration none
                , fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontWeight (int 500)
                , border zero
                , cursor pointer
                , Styles.transitions.base
                , hover
                    [ backgroundColor (hex "D4B76E") -- Slightly lighter on hover
                    ]
                ]
            ]
            [ Icon.icon Icon.Plus Icon.Medium (hex "0F0F0F")
            , text "Create Configuration"
            ]
        ]


-- HELPER FUNCTIONS


truncateText : Int -> String -> String
truncateText maxLength text =
    if String.length text > maxLength then
        String.left maxLength text ++ "..."

    else
        text


pdfModelShortName : PdfModel -> String
pdfModelShortName model =
    case model of
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
