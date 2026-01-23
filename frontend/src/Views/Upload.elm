module Views.Upload exposing (view)

{-| Upload page with sidebar layout matching Pencil design (r1Bae)

Layout structure:
- AppLayout wrapper with sidebar (280px)
- Header: Breadcrumb + Title + Actions (search, notification)
- Content split: Left (main form) + Right panel (360px - recent jobs)

-}

import Components.AppLayout as AppLayout
import Components.Badge as Badge
import Components.Button as Button
import Components.FileUpload as FileUpload
import Components.Icon as Icon
import Components.Input as Input
import Components.Select as Select
import Css exposing (..)
import File
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, for, href, id, placeholder, type_, value)
import Html.Styled.Events exposing (on, onClick, onInput)
import Json.Decode as Decode
import Styles
import Time
import Types exposing (..)


view : PdfModel -> Model -> Html Msg
view pdfModel model =
    AppLayout.view
        { currentRoute = Upload pdfModel
        , userName = "User"
        , userEmail = "user@example.com"
        , showUpgradeCard = True
        , isAdmin = False
        , onSignOut = SignOutClicked
        }
        [ -- Header section
          pageHeader

        -- Main content
        , mainContent pdfModel model
        ]


{-| Page header with breadcrumb, title, and action buttons
Based on uploadHeader (Jq3R3)
-}
pageHeader : Html Msg
pageHeader =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent spaceBetween
            , width (pct 100)
            ]
        ]
        [ -- Left: Breadcrumb + Title
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "4px"
                ]
            ]
            [ -- Breadcrumb
              div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 11)
                    , fontWeight (int 500)
                    , color Styles.colors.foregroundSubtle
                    , letterSpacing (px 0.5)
                    ]
                ]
                [ text "Dashboard / Upload" ]

            -- Title
            , h1
                [ css
                    [ fontFamilies Styles.displayFontStack
                    , fontSize (px 36)
                    , fontWeight (int 400)
                    , color Styles.colors.foreground
                    , margin zero
                    ]
                ]
                [ text "Upload Document" ]
            ]

        -- Right: Action buttons
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "12px"
                ]
            ]
            [ -- Search button (icon only)
              button
                [ css
                    [ displayFlex
                    , alignItems center
                    , justifyContent center
                    , width (px 40)
                    , height (px 40)
                    , backgroundColor transparent
                    , border zero
                    , borderRadius zero
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.activeBg
                        ]
                    ]
                , Attr.type_ "button"
                ]
                [ Icon.icon Icon.Search Icon.Medium Styles.colors.foregroundSubtle ]

            -- Notification button (icon only)
            , button
                [ css
                    [ displayFlex
                    , alignItems center
                    , justifyContent center
                    , width (px 40)
                    , height (px 40)
                    , backgroundColor transparent
                    , border zero
                    , borderRadius zero
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.activeBg
                        ]
                    ]
                , Attr.type_ "button"
                ]
                [ Icon.icon Icon.Bell Icon.Medium Styles.colors.foregroundSubtle ]
            ]
        ]


{-| Main content area split into left form and right panel
Based on uploadContent (FuUID)
-}
mainContent : PdfModel -> Model -> Html Msg
mainContent pdfModel model =
    div
        [ css
            [ displayFlex
            , property "gap" "32px"
            , height (pct 100)
            , width (pct 100)
            ]
        ]
        [ -- Left: Main upload form
          uploadFormSection pdfModel model

        -- Right: Recent jobs panel (360px width)
        , recentJobsPanel model
        ]


{-| Left upload form section
Based on uploadLeft (vIgqy)
-}
uploadFormSection : PdfModel -> Model -> Html Msg
uploadFormSection pdfModel model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "24px"
            , flex (int 1)
            ]
        ]
        [ -- Model selector
          modelSelectorSection pdfModel

        -- File upload section
        , fileUploadSection model.upload pdfModel

        -- Custom prompt section
        , promptSection pdfModel model.upload

        -- Configuration section
        , configurationSection pdfModel model

        -- Submit button
        , submitSection model.upload pdfModel
        ]


{-| Model selector section
Based on modelSelector (QiIPN)
-}
modelSelectorSection : PdfModel -> Html Msg
modelSelectorSection pdfModel =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "12px"
            , width (pct 100)
            ]
        ]
        [ -- Label row
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , width (pct 100)
                ]
            ]
            [ span
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 10)
                    , fontWeight (int 600)
                    , color Styles.colors.primary
                    , letterSpacing (px 1)
                    ]
                ]
                [ text "MODEL" ]
            , span
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 11)
                    , fontWeight (int 500)
                    , color Styles.colors.foregroundSubtle
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ color Styles.colors.foreground
                        , textDecoration underline
                        ]
                    ]
                , onClick OpenModelPalette
                ]
                [ text "Change model (⌘K)" ]
            ]

        -- Model card
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "16px"
                , padding (px 20)
                , border3 (px 1) solid Styles.colors.border
                , borderRadius zero
                , width (pct 100)
                ]
            ]
            [ -- Model icon (44x44 frame with 20x20 icon inside)
              div
                [ css
                    [ displayFlex
                    , alignItems center
                    , justifyContent center
                    , width (px 44)
                    , height (px 44)
                    , border3 (px 1) solid Styles.colors.borderEmphasis
                    , borderRadius zero
                    , flexShrink (int 0)
                    ]
                ]
                [ Icon.icon Icon.FileText Icon.Medium Styles.colors.primary ]

            -- Model info
            , div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "4px"
                    , flex (int 1)
                    ]
                ]
                [ div
                    [ css
                        [ fontFamilies Styles.displayFontStack
                        , fontSize (px 18)
                        , fontWeight (int 400)
                        , color Styles.colors.foreground
                        ]
                    ]
                    [ text (pdfModelToDisplayName pdfModel) ]
                , div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 12)
                        , fontWeight (int 400)
                        , color Styles.colors.foregroundMuted
                        , lineHeight (num 1.5)
                        ]
                    ]
                    [ text (modelDescription pdfModel) ]
                ]

            -- Model badges
            , div
                [ css
                    [ displayFlex
                    , property "gap" "8px"
                    ]
                ]
                [ Badge.badge Badge.Default "GPU"
                , Badge.badge Badge.Default "94.2%"
                ]
            ]
        ]


{-| File upload section
Based on fileUploadSection (asnda)
-}
fileUploadSection : UploadState -> PdfModel -> Html Msg
fileUploadSection uploadState pdfModel =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "12px"
            , width (pct 100)
            ]
        ]
        [ -- Label
          span
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 10)
                , fontWeight (int 600)
                , color Styles.colors.primary
                , letterSpacing (px 1)
                ]
            ]
            [ text "DOCUMENT" ]

        -- File upload area (height 180px)
        , div
            [ css
                [ width (pct 100)
                , height (px 180)
                ]
            ]
            [ FileUpload.fileUpload "file-upload-input" FileSelectedFromValue
            ]
        ]


{-| Custom prompt section
Based on promptSection (xY0td)
-}
promptSection : PdfModel -> UploadState -> Html Msg
promptSection pdfModel uploadState =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "12px"
            , width (pct 100)
            ]
        ]
        [ -- Label
          span
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 10)
                , fontWeight (int 600)
                , color Styles.colors.primary
                , letterSpacing (px 1)
                ]
            ]
            [ text "CUSTOM PROMPT (OPTIONAL)" ]

        -- Textarea (disabled in design)
        , Input.textarea
            { label = "Custom prompt"
            , value = uploadState.prompt
            , onInput = PromptChanged
            , placeholder = "Enter specific instructions for document processing..."
            , hasError = False
            }
        ]


{-| Configuration section
Based on configSection (KQYFZ)
-}
configurationSection : PdfModel -> Model -> Html Msg
configurationSection pdfModel model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "12px"
            , width (pct 100)
            ]
        ]
        [ -- Label
          span
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 10)
                , fontWeight (int 600)
                , color Styles.colors.primary
                , letterSpacing (px 1)
                ]
            ]
            [ text "CONFIGURATION (OPTIONAL)" ]

        -- Select dropdown (disabled in design)
        , Select.select
            { label = ""
            , value = "default"
            , options = [ ( "default", "Use default settings" ) ]
            , onInput = \_ -> SubmitJobClicked -- Placeholder
            , placeholder = "Use default settings"
            }
        ]


{-| Submit section with Process Document button
Based on uploadActions (vUTR1)
-}
submitSection : UploadState -> PdfModel -> Html Msg
submitSection uploadState pdfModel =
    let
        canSubmit =
            uploadState.selectedFile /= Nothing && not uploadState.submitting
    in
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "12px"
            , paddingTop (px 16)
            , width (pct 100)
            ]
        ]
        [ if canSubmit then
            Button.buttonWithIcon Button.Primary Icon.Send "Process Document" SubmitJobClicked

          else
            Button.buttonDisabled Button.Primary "Process Document"
        ]


{-| Recent jobs panel (right side, 360px width)
Based on uploadRight (G73D7) and recentJobsSection (czl6r)
-}
recentJobsPanel : Model -> Html Msg
recentJobsPanel model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "24px"
            , width (px 360)
            ]
        ]
        [ recentJobsSection model
        ]


{-| Recent jobs section
-}
recentJobsSection : Model -> Html Msg
recentJobsSection model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "16px"
            ]
        ]
        [ -- Header
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , width (pct 100)
                ]
            ]
            [ span
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 10)
                    , fontWeight (int 600)
                    , color Styles.colors.primary
                    , letterSpacing (px 1)
                    ]
                ]
                [ text "RECENT JOBS" ]
            , a
                [ href (routeToPath Jobs)
                , css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 11)
                    , fontWeight (int 500)
                    , color Styles.colors.foregroundSubtle
                    , textDecoration none
                    , Styles.transitions.base
                    , hover
                        [ color Styles.colors.foreground
                        , textDecoration underline
                        ]
                    ]
                ]
                [ text "View all" ]
            ]

        -- Jobs list
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , border3 (px 1) solid Styles.colors.border
                , borderRadius zero
                ]
            ]
            (if List.isEmpty model.jobs.jobs then
                [ emptyJobsMessage ]

             else
                List.indexedMap (recentJobItem (List.length model.jobs.jobs)) (List.take 3 model.jobs.jobs)
            )
        ]


{-| Empty jobs message
-}
emptyJobsMessage : Html Msg
emptyJobsMessage =
    div
        [ css
            [ padding (px 24)
            , textAlign center
            ]
        ]
        [ div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 13)
                , color Styles.colors.foregroundMuted
                ]
            ]
            [ text "No recent jobs" ]
        ]


{-| Recent job item
Based on job items from k4Urv list
-}
recentJobItem : Int -> Int -> Job -> Html Msg
recentJobItem totalJobs index job =
    let
        isLastItem =
            index == totalJobs - 1 || index == 2

        ( iconName, iconColor, iconBgColor ) =
            case job.status of
                Complete ->
                    ( Icon.Check, Styles.colors.success, Styles.colors.successMuted )

                Processing ->
                    ( Icon.Info, Styles.colors.info, Styles.colors.infoMuted )

                _ ->
                    ( Icon.Check, Styles.colors.success, Styles.colors.successMuted )

        statusBadge =
            case job.status of
                Complete ->
                    Badge.badge Badge.Success "Complete"

                Processing ->
                    Badge.badge Badge.Info "Processing"

                _ ->
                    Badge.badge Badge.Success "Complete"
    in
    div
        [ css
            ([ displayFlex
             , alignItems center
             , property "gap" "14px"
             , padding (px 16)
             , width (pct 100)
             ]
                ++ (if not isLastItem then
                        [ borderBottom3 (px 1) solid Styles.colors.borderSubtle ]

                    else
                        []
                   )
            )
        ]
        [ -- Icon (32x32 frame with 14x14 icon inside)
          div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent center
                , width (px 32)
                , height (px 32)
                , border3 (px 1) solid iconBgColor
                , borderRadius zero
                , flexShrink (int 0)
                ]
            ]
            [ Icon.icon iconName (Icon.Small) iconColor ]

        -- Job info
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "4px"
                , flex (int 1)
                , overflow hidden
                ]
            ]
            [ div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 13)
                    , fontWeight (int 500)
                    , color Styles.colors.foreground
                    , overflow hidden
                    , textOverflow ellipsis
                    , whiteSpace noWrap
                    ]
                ]
                [ text (Maybe.withDefault "Unknown" job.originalFilename) ]
            , div
                [ css
                    [ fontFamilies [ "JetBrains Mono", "monospace" ]
                    , fontSize (px 11)
                    , fontWeight (int 400)
                    , color Styles.colors.foregroundSubtle
                    ]
                ]
                [ text (pdfModelToDisplayName job.pdfModel ++ " • " ++ formatJobTime job.submittedAt)
                ]
            ]

        -- Status badge
        , statusBadge
        ]


{-| Format job time (relative time)
-}
formatJobTime : Time.Posix -> String
formatJobTime time =
    -- Simplified for now, would need current time to calculate relative time
    "2 min ago"


{-| Get model description
-}
modelDescription : PdfModel -> String
modelDescription model =
    case model of
        Docling ->
            "IBM's document understanding model with high accuracy for tables and structured content"

        Marker ->
            "Fast and efficient document processing with good accuracy"

        Dolphin ->
            "Advanced document understanding with high accuracy"

        _ ->
            "Document processing model"
