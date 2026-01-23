module Views.AdminConfigs exposing (view)

import Components.AppLayout as AppLayout
import Components.Badge as Badge
import Components.Button as Button
import Components.Icon as Icon
import Components.Input as Input
import Components.Tabs as Tabs
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href, placeholder, value)
import Html.Styled.Events exposing (onClick, onInput)
import Styles
import Types
    exposing
        ( ApprovalStatus(..)
        , Configuration
        , Model
        , Msg(..)
        , Route(..)
        , Visibility(..)
        , pdfModelToDisplayName
        )


view : Model -> Html Msg
view model =
    AppLayout.view
        { currentRoute = AdminConfigs
        , userName = "Admin User"
        , userEmail = "admin@example.com"
        , showUpgradeCard = False
        , isAdmin = True
        , onSignOut = SignOutClicked
        }
        [ viewAdminConfigsContent model
        ]


viewAdminConfigsContent : Model -> Html Msg
viewAdminConfigsContent model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "24px"
            , height (pct 100)
            , width (pct 100)
            ]
        ]
        [ -- Header section
          viewHeader

        -- Tabs
        , viewTabs

        -- Content area (pending list + detail panel)
        , viewContentArea model
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "8px"
            , width (pct 100)
            ]
        ]
        [ -- Breadcrumb
          div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 12)
                , fontWeight normal
                , color (hex "666666") -- $--foreground-subtle
                ]
            ]
            [ text "Dashboard / Admin / Configurations" ]

        -- Title section
        , div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , width (pct 100)
                ]
            ]
            [ div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "4px"
                    ]
                ]
                [ -- Title
                  div
                    [ css
                        [ fontFamilies [ "Playfair Display", .value serif ]
                        , fontSize (px 32)
                        , fontWeight (int 500)
                        , color (hex "FAF8F5") -- $--foreground
                        ]
                    ]
                    [ text "Admin Configurations" ]

                -- Subtitle
                , div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 14)
                        , fontWeight normal
                        , color (hex "888888") -- $--foreground-muted
                        ]
                    ]
                    [ text "Review and approve public configuration submissions" ]
                ]
            ]
        ]


viewTabs : Html Msg
viewTabs =
    Tabs.tabs
        [ { label = "Pending Review"
          , value = "pending"
          , isActive = True
          , onSelect = NoOp
          }
        , { label = "Approved"
          , value = "approved"
          , isActive = False
          , onSelect = NoOp
          }
        , { label = "Rejected"
          , value = "rejected"
          , isActive = False
          , onSelect = NoOp
          }
        ]


viewContentArea : Model -> Html Msg
viewContentArea model =
    div
        [ css
            [ displayFlex
            , property "gap" "24px"
            , width (pct 100)
            , height (pct 100)
            , flex (int 1)
            ]
        ]
        [ -- Left: Pending list
          viewPendingList model

        -- Right: Detail panel
        , viewDetailPanel model
        ]


viewPendingList : Model -> Html Msg
viewPendingList model =
    let
        pendingConfigs =
            List.filter (\c -> c.approvalStatus == PendingApproval) model.adminConfigs.pendingConfigs
    in
    div
        [ css
            [ displayFlex
            , flexDirection column
            , width (px 400)
            , height (pct 100)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , backgroundColor (hex "0A0A0A") -- $--card (using sidebar bg as card)
            , overflow hidden
            ]
        ]
        [ -- List header
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , padding (px 16)
                , borderBottom3 (px 1) solid (hex "1F1F1F") -- $--border
                ]
            ]
            [ div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight (int 600)
                    , color (hex "FAF8F5") -- $--foreground
                    ]
                ]
                [ text "Pending Queue" ]
            , Badge.badge Badge.Warning (String.fromInt (List.length pendingConfigs))
            ]

        -- List items
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , height (pct 100)
                , overflowY auto
                ]
            ]
            (if List.isEmpty pendingConfigs then
                [ viewEmptyPendingList ]

             else
                List.map (viewPendingItem model) pendingConfigs
            )
        ]


viewPendingItem : Model -> Configuration -> Html Msg
viewPendingItem model config =
    let
        isSelected =
            model.adminConfigs.approveConfirmation == Just config.configId
    in
    div
        [ onClick (ShowApproveConfirmation config.configId)
        , css
            [ displayFlex
            , flexDirection column
            , property "gap" "8px"
            , padding (px 16)
            , borderBottom3 (px 1) solid (hex "1F1F1F") -- $--border
            , cursor pointer
            , Styles.transitions.base
            , if isSelected then
                backgroundColor (rgba 201 169 98 0.063) -- $--active-bg

              else
                backgroundColor transparent
            , hover
                [ backgroundColor (rgba 201 169 98 0.063) -- $--active-bg
                ]
            ]
        ]
        [ -- Name and badge row
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , width (pct 100)
                ]
            ]
            [ div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight (int 500)
                    , color (hex "FAF8F5") -- $--foreground
                    ]
                ]
                [ text config.name ]
            , Badge.badge Badge.Warning "Pending"
            ]

        -- Meta information
        , div
            [ css
                [ displayFlex
                , property "gap" "12px"
                ]
            ]
            [ div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 12)
                    , fontWeight normal
                    , color (hex "888888") -- $--foreground-muted
                    ]
                ]
                [ text ("Model: " ++ pdfModelShortName config.model) ]
            , div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 12)
                    , fontWeight normal
                    , color (hex "888888") -- $--foreground-muted
                    ]
                ]
                [ text ("By: " ++ config.userId) ]
            ]

        -- Submitted date
        , div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 11)
                , fontWeight normal
                , color (hex "666666") -- $--foreground-subtle
                ]
            ]
            [ text "Submitted: Jan 20, 2026" ]
        ]


viewEmptyPendingList : Html Msg
viewEmptyPendingList =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , padding (px 40)
            , textAlign center
            ]
        ]
        [ div
            [ css
                [ fontSize (px 48)
                , marginBottom (px 16)
                , opacity (num 0.3)
                ]
            ]
            [ text "✅" ]
        , div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , color (hex "888888")
                ]
            ]
            [ text "No pending configurations" ]
        ]


viewDetailPanel : Model -> Html Msg
viewDetailPanel model =
    let
        selectedConfig =
            case model.adminConfigs.approveConfirmation of
                Just configId ->
                    List.filter (\c -> c.configId == configId) model.adminConfigs.pendingConfigs
                        |> List.head

                Nothing ->
                    Nothing
    in
    case selectedConfig of
        Just config ->
            viewConfigDetails model config

        Nothing ->
            viewEmptyDetailPanel


viewEmptyDetailPanel : Html Msg
viewEmptyDetailPanel =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , flex (int 1)
            , height (pct 100)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , backgroundColor (hex "0A0A0A") -- $--card
            ]
        ]
        [ div
            [ css
                [ fontSize (px 48)
                , marginBottom (px 16)
                , opacity (num 0.3)
                ]
            ]
            [ text "📋" ]
        , div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , color (hex "888888")
                ]
            ]
            [ text "Select a configuration to review" ]
        ]


viewConfigDetails : Model -> Configuration -> Html Msg
viewConfigDetails model config =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , flex (int 1)
            , height (pct 100)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , backgroundColor (hex "0A0A0A") -- $--card
            , overflow hidden
            ]
        ]
        [ -- Detail header
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , padding (px 20)
                , borderBottom3 (px 1) solid (hex "1F1F1F") -- $--border
                ]
            ]
            [ div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 16)
                    , fontWeight (int 600)
                    , color (hex "FAF8F5") -- $--foreground
                    ]
                ]
                [ text "Configuration Details" ]
            , button
                [ onClick CancelApproveConfig
                , css
                    [ backgroundColor transparent
                    , border zero
                    , padding (px 8)
                    , cursor pointer
                    , borderRadius (px 6)
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor (hex "1F1F1F")
                        ]
                    ]
                ]
                [ Icon.icon Icon.X Icon.Medium (hex "666666") ]
            ]

        -- Detail content
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "24px"
                , padding (px 24)
                , height (pct 100)
                , overflowY auto
                ]
            ]
            [ -- Config info
              div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "16px"
                    ]
                ]
                [ -- Configuration name
                  div
                    [ css
                        [ displayFlex
                        , flexDirection column
                        , property "gap" "4px"
                        ]
                    ]
                    [ div
                        [ css
                            [ fontFamilies Styles.fontStack
                            , fontSize (px 11)
                            , fontWeight (int 500)
                            , letterSpacing (px 0.5)
                            , color (hex "666666") -- $--foreground-subtle
                            ]
                        ]
                        [ text "CONFIGURATION NAME" ]
                    , div
                        [ css
                            [ fontFamilies Styles.fontStack
                            , fontSize (px 18)
                            , fontWeight (int 600)
                            , color (hex "FAF8F5") -- $--foreground
                            ]
                        ]
                        [ text config.name ]
                    ]

                -- Info row (model, visibility, created by)
                , div
                    [ css
                        [ displayFlex
                        , property "gap" "32px"
                        , width (pct 100)
                        ]
                    ]
                    [ viewInfoField "Model" (pdfModelShortName config.model)
                    , viewInfoField "Visibility" (visibilityToString config.visibility)
                    , viewInfoField "Created By" config.userId
                    ]

                -- Description
                , case config.description of
                    Just desc ->
                        div
                            [ css
                                [ displayFlex
                                , flexDirection column
                                , property "gap" "4px"
                                ]
                            ]
                            [ div
                                [ css
                                    [ fontFamilies Styles.fontStack
                                    , fontSize (px 11)
                                    , fontWeight (int 500)
                                    , letterSpacing (px 0.5)
                                    , color (hex "666666") -- $--foreground-subtle
                                    ]
                                ]
                                [ text "DESCRIPTION" ]
                            , div
                                [ css
                                    [ fontFamilies Styles.fontStack
                                    , fontSize (px 14)
                                    , fontWeight normal
                                    , lineHeight (num 1.5)
                                    , color (hex "FAF8F5") -- $--foreground
                                    ]
                                ]
                                [ text desc ]
                            ]

                    Nothing ->
                        text ""

                -- Parameters section
                , div
                    [ css
                        [ displayFlex
                        , flexDirection column
                        , property "gap" "8px"
                        ]
                    ]
                    [ div
                        [ css
                            [ fontFamilies Styles.fontStack
                            , fontSize (px 11)
                            , fontWeight (int 500)
                            , letterSpacing (px 0.5)
                            , color (hex "666666") -- $--foreground-subtle
                            ]
                        ]
                        [ text "PARAMETERS" ]
                    , div
                        [ css
                            [ padding (px 16)
                            , backgroundColor (hex "0F0F0F")
                            , border3 (px 1) solid (hex "1F1F1F")
                            , borderRadius (px 6)
                            , fontFamilies [ "JetBrains Mono", .value monospace ]
                            , fontSize (px 12)
                            , color (hex "888888")
                            , overflowX auto
                            ]
                        ]
                        [ text (configToJsonPreview config) ]
                    ]
                ]

            -- Divider
            , div
                [ css
                    [ width (pct 100)
                    , height (px 1)
                    , backgroundColor (hex "1F1F1F") -- $--border
                    ]
                ]
                []

            -- Review section
            , div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "16px"
                    ]
                ]
                [ div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 14)
                        , fontWeight (int 600)
                        , color (hex "FAF8F5") -- $--foreground
                        ]
                    ]
                    [ text "Review Decision" ]

                -- Review notes textarea
                , Input.textarea
                    { label = "Review Notes (optional)"
                    , value = model.adminConfigs.rejectionReason
                    , placeholder = "Add notes about your decision..."
                    , onInput = RejectReasonChanged
                    , hasError = False
                    }

                -- Action buttons
                , div
                    [ css
                        [ displayFlex
                        , justifyContent flexEnd
                        , property "gap" "12px"
                        , width (pct 100)
                        ]
                    ]
                    [ Button.buttonWithIcon
                        Button.Danger
                        Icon.X
                        "Reject"
                        (Types.ConfirmApproveConfig config.configId)
                    , Button.buttonWithIcon
                        Button.Primary
                        Icon.Check
                        "Approve"
                        (Types.ConfirmApproveConfig config.configId)
                    ]
                ]
            ]
        ]


viewInfoField : String -> String -> Html Msg
viewInfoField label value =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "4px"
            ]
        ]
        [ div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 11)
                , fontWeight (int 500)
                , letterSpacing (px 0.5)
                , color (hex "666666") -- $--foreground-subtle
                ]
            ]
            [ text label ]
        , div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontWeight normal
                , color (hex "FAF8F5") -- $--foreground
                ]
            ]
            [ text value ]
        ]


-- HELPER FUNCTIONS


pdfModelShortName : Types.PdfModel -> String
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


visibilityToString : Visibility -> String
visibilityToString visibility =
    case visibility of
        Private ->
            "Private"

        Public ->
            "Public"


configToJsonPreview : Configuration -> String
configToJsonPreview config =
    "{\n  \"model\": \"" ++ pdfModelShortName config.model ++ "\",\n  \"visibility\": \"" ++ visibilityToString config.visibility ++ "\",\n  \"prompt\": " ++ (case config.inferenceParams.prompt of
        Just p -> "\"" ++ String.left 40 p ++ "...\""
        Nothing -> "null"
    ) ++ "\n  ...\n}"
