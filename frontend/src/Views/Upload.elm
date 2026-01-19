module Views.Upload exposing (view)

import Components.Button as Button
import Components.ModelGrid exposing (modelGrid, modelGridConfig)
import Css exposing (..)
import Css.Animations as Animations
import File
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, for, href, id, placeholder, selected, type_, value)
import Html.Styled.Events exposing (on, onClick, onInput, preventDefaultOn)
import Json.Decode as Decode
import Styles
import Types exposing (ApprovalStatus(..), Configuration, Model, Msg(..), PdfModel, Route(..), UploadState, Visibility(..), defaultPdfModel, defaultPromptForModel, modelSupportsPrompt, pdfModelToDisplayName, routeToPath)


view : PdfModel -> Model -> Html Msg
view pdfModel model =
    div
        [ css
            [ Styles.containerStyle
            , paddingTop Styles.spacing.xxxl
            , minHeight (vh 100)
            ]
        ]
        [ viewHeader
        , div
            [ css
                [ maxWidth (px 640)
                , margin2 Styles.spacing.xxl auto
                ]
            ]
            [ -- Page title
              div
                [ css
                    [ marginBottom Styles.spacing.xxl
                    , textAlign center
                    ]
                ]
                [ h2
                    [ css
                        [ Styles.textDisplay
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    [ text "New Job" ]
                , p
                    [ css
                        [ Styles.textSecondary
                        , margin zero
                        ]
                    ]
                    [ text "Upload a PDF document for processing" ]
                ]

            -- Model selection section
            , div
                [ css [ marginBottom Styles.spacing.xxl ] ]
                [ div
                    [ css
                        [ Styles.flexBetween
                        , marginBottom Styles.spacing.md
                        ]
                    ]
                    [ label
                        [ css
                            [ Styles.textCaption
                            ]
                        ]
                        [ text "SELECT MODEL" ]
                    , button
                        [ onClick OpenModelPalette
                        , css
                            [ backgroundColor Styles.colors.surface
                            , border3 (px 1) solid Styles.colors.border
                            , borderRadius Styles.radius.md
                            , padding2 Styles.spacing.xs Styles.spacing.sm
                            , color Styles.colors.textTertiary
                            , cursor pointer
                            , Css.fontSize Styles.fontSize.caption
                            , fontFamilies Styles.fontStack
                            , Styles.transitions.fast
                            , hover
                                [ borderColor Styles.colors.borderStrong
                                , color Styles.colors.textSecondary
                                ]
                            ]
                        ]
                        [ text "⌘K" ]
                    ]
                , modelGrid
                    (modelGridConfig
                        { selectedModel = pdfModel
                        , hoveredModel = model.hoveredModel
                        , onSelect = ModelSelected
                        , onHover = ModelHovered
                        }
                    )
                , a
                    [ href (routeToPath Models)
                    , css
                        [ display block
                        , textAlign center
                        , marginTop Styles.spacing.lg
                        , Css.fontSize Styles.fontSize.small
                        , color Styles.colors.textTertiary
                        , textDecoration none
                        , Styles.transitions.fast
                        , hover [ color Styles.colors.accent ]
                        ]
                    ]
                    [ text "Explore all models →" ]
                ]

            -- Main card for file upload
            , div
                [ css
                    [ backgroundColor Styles.colors.surface
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.xl
                    , padding Styles.spacing.xxl
                    ]
                ]
                [ viewConfigSelector pdfModel model
                , viewPromptInput pdfModel model.upload
                , viewFileDropZone model.upload pdfModel
                , case model.upload.error of
                    Just err ->
                        div
                            [ css
                                [ backgroundColor Styles.colors.errorMuted
                                , border3 (px 1) solid Styles.colors.error
                                , borderRadius Styles.radius.md
                                , padding Styles.spacing.base
                                , marginTop Styles.spacing.lg
                                , Styles.flexRow
                                , Styles.gap Styles.spacing.sm
                                ]
                            ]
                            [ span
                                [ css [ color Styles.colors.error ] ]
                                [ text err ]
                            ]

                    Nothing ->
                        text ""
                ]
            ]
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ Styles.flexBetween
            , marginBottom Styles.spacing.xxl
            ]
        ]
        [ div []
            [ a
                [ href (routeToPath (Upload defaultPdfModel))
                , css
                    [ Styles.textH1
                    , color Styles.colors.textPrimary
                    , textDecoration none
                    , hover [ color Styles.colors.accent ]
                    ]
                ]
                [ text "PDF Models" ]
            ]
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.md
                ]
            ]
            [ a
                [ href (routeToPath Models)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.overlay
                        , borderColor Styles.colors.borderStrong
                        ]
                    ]
                ]
                [ text "Models" ]
            , a
                [ href (routeToPath Configs)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.overlay
                        , borderColor Styles.colors.borderStrong
                        ]
                    ]
                ]
                [ text "Configs" ]
            , a
                [ href (routeToPath Jobs)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.overlay
                        , borderColor Styles.colors.borderStrong
                        ]
                    ]
                ]
                [ text "Dashboard" ]
            , Button.button Button.Ghost "Sign Out" SignOutClicked
            ]
        ]


viewConfigSelector : PdfModel -> Model -> Html Msg
viewConfigSelector pdfModel model =
    let
        -- Filter configurations for the current model that are approved
        approvedConfigs =
            model.configs.configurations
                |> List.filter (\c -> c.model == pdfModel && c.approvalStatus == Approved)

        -- All configs for this model (for showing pending/rejected)
        allModelConfigs =
            model.configs.configurations
                |> List.filter (\c -> c.model == pdfModel)
    in
    if List.isEmpty allModelConfigs then
        -- No configs at all, show link to create one
        div
            [ css
                [ marginBottom Styles.spacing.xl
                ]
            ]
            [ label
                [ css
                    [ display block
                    , Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "CONFIGURATION (OPTIONAL)" ]
            , a
                [ href (routeToPath Configs)
                , css
                    [ display block
                    , padding Styles.spacing.base
                    , backgroundColor Styles.colors.surfaceRaised
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textTertiary
                    , textDecoration none
                    , Styles.transitions.base
                    , hover
                        [ borderColor Styles.colors.borderStrong
                        , color Styles.colors.textSecondary
                        ]
                    ]
                ]
                [ text "Create a custom configuration →" ]
            ]

    else
        div
            [ css
                [ marginBottom Styles.spacing.xl
                ]
            ]
            [ label
                [ css
                    [ display block
                    , Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "CONFIGURATION (OPTIONAL)" ]
            , div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , Styles.gap Styles.spacing.sm
                    ]
                ]
                ([ viewConfigOption Nothing model.upload.selectedConfig ]
                    ++ List.map (\config -> viewConfigOption (Just config) model.upload.selectedConfig) allModelConfigs
                )
            , a
                [ href (routeToPath Configs)
                , css
                    [ display block
                    , marginTop Styles.spacing.sm
                    , Css.fontSize Styles.fontSize.small
                    , color Styles.colors.textTertiary
                    , textDecoration none
                    , Styles.transitions.fast
                    , hover [ color Styles.colors.accent ]
                    ]
                ]
                [ text "Manage configurations →" ]
            ]


viewConfigOption : Maybe Configuration -> Maybe Configuration -> Html Msg
viewConfigOption maybeConfig selectedConfig =
    let
        isSelected =
            case ( maybeConfig, selectedConfig ) of
                ( Nothing, Nothing ) ->
                    True

                ( Just config, Just selected ) ->
                    config.configId == selected.configId

                _ ->
                    False

        ( label, isDisabled, statusIndicator ) =
            case maybeConfig of
                Nothing ->
                    ( "Default (no custom configuration)", False, text "" )

                Just config ->
                    let
                        statusBadge =
                            case config.approvalStatus of
                                PendingApproval ->
                                    span
                                        [ css
                                            [ Css.fontSize Styles.fontSize.caption
                                            , color Styles.colors.warning
                                            , backgroundColor Styles.colors.warningMuted
                                            , padding2 Styles.spacing.xs Styles.spacing.sm
                                            , borderRadius Styles.radius.full
                                            , marginLeft Styles.spacing.sm
                                            ]
                                        ]
                                        [ text "Pending" ]

                                Rejected ->
                                    span
                                        [ css
                                            [ Css.fontSize Styles.fontSize.caption
                                            , color Styles.colors.error
                                            , backgroundColor Styles.colors.errorMuted
                                            , padding2 Styles.spacing.xs Styles.spacing.sm
                                            , borderRadius Styles.radius.full
                                            , marginLeft Styles.spacing.sm
                                            ]
                                        ]
                                        [ text "Rejected" ]

                                Approved ->
                                    span
                                        [ css
                                            [ Css.fontSize Styles.fontSize.caption
                                            , color Styles.colors.success
                                            , backgroundColor Styles.colors.successMuted
                                            , padding2 Styles.spacing.xs Styles.spacing.sm
                                            , borderRadius Styles.radius.full
                                            , marginLeft Styles.spacing.sm
                                            ]
                                        ]
                                        [ text "✓" ]
                    in
                    ( config.name
                    , config.approvalStatus /= Approved
                    , statusBadge
                    )
    in
    div
        [ css
            ([ padding Styles.spacing.base
             , backgroundColor
                (if isSelected then
                    Styles.colors.accentMuted

                 else
                    Styles.colors.surfaceRaised
                )
             , border3 (px 1) solid
                (if isSelected then
                    Styles.colors.accent

                 else
                    Styles.colors.border
                )
             , borderRadius Styles.radius.md
             , Styles.transitions.base
             , Styles.flexRow
             , justifyContent spaceBetween
             ]
                ++ (if isDisabled then
                        [ opacity (num 0.6)
                        , cursor notAllowed
                        ]

                    else
                        [ cursor pointer
                        , hover
                            [ borderColor
                                (if isSelected then
                                    Styles.colors.accent

                                 else
                                    Styles.colors.borderStrong
                                )
                            ]
                        ]
                   )
            )
        , if isDisabled then
            Attr.attribute "aria-disabled" "true"

          else
            onClick (SelectConfigForUpload maybeConfig)
        ]
        [ div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.sm
                ]
            ]
            [ -- Radio indicator
              div
                [ css
                    [ Css.width (px 16)
                    , Css.height (px 16)
                    , borderRadius (pct 50)
                    , border3 (px 2) solid
                        (if isSelected then
                            Styles.colors.accent

                         else
                            Styles.colors.border
                        )
                    , displayFlex
                    , alignItems center
                    , justifyContent center
                    ]
                ]
                [ if isSelected then
                    div
                        [ css
                            [ Css.width (px 8)
                            , Css.height (px 8)
                            , borderRadius (pct 50)
                            , backgroundColor Styles.colors.accent
                            ]
                        ]
                        []

                  else
                    text ""
                ]
            , span
                [ css
                    [ color
                        (if isSelected then
                            Styles.colors.accent

                         else
                            Styles.colors.textPrimary
                        )
                    , fontWeight
                        (if isSelected then
                            Styles.fontWeights.medium

                         else
                            Styles.fontWeights.normal
                        )
                    ]
                ]
                [ text label ]
            ]
        , statusIndicator
        ]


viewPromptInput : PdfModel -> UploadState -> Html Msg
viewPromptInput pdfModel uploadState =
    if modelSupportsPrompt pdfModel then
        div
            [ css
                [ marginBottom Styles.spacing.xl
                ]
            ]
            [ label
                [ css
                    [ display block
                    , Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "CUSTOM PROMPT (OPTIONAL)" ]
            , textarea
                [ onInput PromptChanged
                , value uploadState.prompt
                , placeholder "Enter custom instructions for the model..."
                , css
                    [ Css.width (pct 100)
                    , padding Styles.spacing.base
                    , backgroundColor Styles.colors.surfaceRaised
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textPrimary
                    , fontFamilies Styles.fontStack
                    , Css.fontSize Styles.fontSize.body
                    , Css.minHeight (px 100)
                    , resize vertical
                    , Styles.transitions.base
                    , hover
                        [ borderColor Styles.colors.borderStrong
                        ]
                    , focus
                        [ borderColor Styles.colors.borderFocus
                        , Styles.focusRing
                        ]
                    , Css.pseudoElement "placeholder"
                        [ color Styles.colors.textTertiary
                        ]
                    ]
                ]
                []
            , p
                [ css
                    [ Styles.textSmall
                    , marginTop Styles.spacing.sm
                    , color Styles.colors.textTertiary
                    ]
                ]
                [ text "Provide custom instructions to guide how the model processes this document." ]
            ]

    else
        text ""


viewFileDropZone : UploadState -> PdfModel -> Html Msg
viewFileDropZone uploadState pdfModel =
    let
        hasFile =
            uploadState.selectedFile /= Nothing

        isUploading =
            uploadState.uploadProgress /= Nothing || uploadState.submitting
    in
    div []
        [ label
            [ css
                [ display block
                , Styles.textCaption
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "DOCUMENT" ]
        , div
            [ css
                [ border3 (px 2) dashed
                    (if hasFile then
                        Styles.colors.accent

                     else
                        Styles.colors.border
                    )
                , borderRadius Styles.radius.lg
                , padding Styles.spacing.xxl
                , textAlign center
                , backgroundColor
                    (if hasFile then
                        Styles.colors.accentMuted

                     else
                        Styles.colors.surfaceRaised
                    )
                , Styles.transitions.base
                , cursor pointer
                , hover
                    [ borderColor
                        (if hasFile then
                            Styles.colors.accentHover

                         else
                            Styles.colors.borderStrong
                        )
                    , backgroundColor
                        (if hasFile then
                            Styles.colors.accentMuted

                         else
                            Styles.colors.overlay
                        )
                    ]
                ]
            ]
            [ case uploadState.selectedFile of
                Just file ->
                    viewSelectedFile file uploadState pdfModel

                Nothing ->
                    viewDropPrompt
            ]
        , input
            [ type_ "file"
            , id "file-input"
            , on "change" (Decode.map FileSelected fileDecoder)
            , css
                [ display none
                ]
            ]
            []
        ]


viewDropPrompt : Html Msg
viewDropPrompt =
    label
        [ for "file-input"
        , css
            [ display block
            , cursor pointer
            ]
        ]
        [ div
            [ css
                [ Css.fontSize (px 40)
                , marginBottom Styles.spacing.md
                , opacity (num 0.4)
                ]
            ]
            [ text "📄" ]
        , div
            [ css
                [ Styles.textBody
                , marginBottom Styles.spacing.xs
                ]
            ]
            [ span [ css [ color Styles.colors.accent ] ] [ text "Click to upload" ]
            , text " or drag and drop"
            ]
        , div
            [ css
                [ Styles.textSmall
                , color Styles.colors.textTertiary
                ]
            ]
            [ text "PDF files only" ]
        ]


viewSelectedFile : File.File -> UploadState -> PdfModel -> Html Msg
viewSelectedFile file uploadState pdfModel =
    div []
        [ div
            [ css
                [ Css.fontSize (px 40)
                , marginBottom Styles.spacing.md
                ]
            ]
            [ text "✓" ]
        , div
            [ css
                [ fontWeight Styles.fontWeights.medium
                , color Styles.colors.textPrimary
                , marginBottom Styles.spacing.xs
                ]
            ]
            [ text (File.name file) ]
        , div
            [ css
                [ Styles.textSmall
                , color Styles.colors.textSecondary
                , marginBottom Styles.spacing.lg
                ]
            ]
            [ text (formatFileSize (File.size file)) ]
        , -- Progress or submit button
          case uploadState.uploadProgress of
            Just progress ->
                viewProgressBar progress

            Nothing ->
                if uploadState.submitting then
                    div
                        [ css
                            [ color Styles.colors.accent
                            , Styles.flexRow
                            , justifyContent center
                            , Styles.gap Styles.spacing.sm
                            ]
                        ]
                        [ span
                            [ css
                                [ display inlineBlock
                                , animationName spinAnimation
                                , animationDuration (ms 1000)
                                , property "animation-iteration-count" "infinite"
                                , property "animation-timing-function" "linear"
                                ]
                            ]
                            [ text "◐" ]
                        , text "Submitting job..."
                        ]

                else
                    div
                        [ css
                            [ Styles.flexRow
                            , justifyContent center
                            , Styles.gap Styles.spacing.md
                            ]
                        ]
                        [ label
                            [ for "file-input"
                            , css
                                [ padding2 Styles.spacing.sm Styles.spacing.base
                                , border3 (px 1) solid Styles.colors.border
                                , borderRadius Styles.radius.md
                                , color Styles.colors.textSecondary
                                , cursor pointer
                                , Css.fontSize Styles.fontSize.body
                                , fontWeight Styles.fontWeights.medium
                                , Styles.transitions.base
                                , hover
                                    [ backgroundColor Styles.colors.overlay
                                    , borderColor Styles.colors.borderStrong
                                    ]
                                ]
                            ]
                            [ text "Change File" ]
                        , Button.button Button.Primary "Start Processing" SubmitJobClicked
                        ]
        ]


viewProgressBar : Float -> Html msg
viewProgressBar progress =
    let
        percent =
            Basics.round (progress * 100)
    in
    div
        [ css
            [ Css.width (pct 100)
            , maxWidth (px 300)
            , margin2 zero auto
            ]
        ]
        [ div
            [ css
                [ Styles.flexBetween
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ span
                [ css [ Styles.textSmall, color Styles.colors.textSecondary ]
                ]
                [ text "Uploading..." ]
            , span
                [ css [ Styles.textSmall, color Styles.colors.accent ]
                ]
                [ text (String.fromInt percent ++ "%") ]
            ]
        , div
            [ css
                [ Css.height (px 4)
                , backgroundColor Styles.colors.border
                , borderRadius Styles.radius.full
                , overflow Css.hidden
                ]
            ]
            [ div
                [ css
                    [ Css.height (pct 100)
                    , Css.width (pct (toFloat percent))
                    , backgroundColor Styles.colors.accent
                    , borderRadius Styles.radius.full
                    , Styles.transitions.base
                    , property "box-shadow" "0 0 8px rgba(34, 211, 238, 0.5)"
                    ]
                ]
                []
            ]
        ]


spinAnimation : Animations.Keyframes {}
spinAnimation =
    Animations.keyframes
        [ ( 0, [ Animations.transform [ rotate (deg 0) ] ] )
        , ( 100, [ Animations.transform [ rotate (deg 360) ] ] )
        ]


formatFileSize : Int -> String
formatFileSize bytes =
    if bytes < 1024 then
        String.fromInt bytes ++ " B"

    else if bytes < 1024 * 1024 then
        String.fromInt (bytes // 1024) ++ " KB"

    else
        String.fromFloat (toFloat bytes / (1024 * 1024) |> (\f -> toFloat (Basics.round (f * 10)) / 10)) ++ " MB"


fileDecoder : Decode.Decoder File.File
fileDecoder =
    Decode.at [ "target", "files", "0" ] File.decoder
