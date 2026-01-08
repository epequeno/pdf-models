module Views.Upload exposing (view)

import Components.Button as Button
import Css exposing (..)
import File
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, for, href, id, placeholder, selected, type_, value)
import Html.Styled.Events exposing (on, onClick, onInput)
import Json.Decode as Decode
import Styles
import Types exposing (..)


view : PdfModel -> Model -> Html Msg
view pdfModel model =
    div
        [ css
            [ Styles.containerStyle
            , paddingTop Styles.spacing.xl
            ]
        ]
        [ viewHeader model
        , div
            [ css
                [ maxWidth (px 600)
                , margin2 Styles.spacing.xxl auto
                ]
            ]
            [ h2
                [ css
                    [ Css.fontSize Styles.fontSize.h2
                    , fontWeight Styles.fontWeight.semibold
                    , marginBottom Styles.spacing.lg
                    , color Styles.colors.textPrimary
                    ]
                ]
                [ text "Upload PDF" ]
            , div
                [ css
                    [ border3 (px 1) solid Styles.colors.border
                    , padding Styles.spacing.xl
                    , backgroundColor Styles.colors.surface
                    ]
                ]
                [ viewModelSelector pdfModel
                , viewModelInfo pdfModel model.upload.modelInfoExpanded
                , viewPromptInput pdfModel model.upload
                , viewFileInput model.upload
                , case model.upload.selectedFile of
                    Just file ->
                        viewSelectedFile file model.upload

                    Nothing ->
                        text ""
                , case model.upload.error of
                    Just err ->
                        div
                            [ css
                                [ color Styles.colors.accentError
                                , Css.fontSize Styles.fontSize.small
                                , marginTop Styles.spacing.md
                                ]
                            ]
                            [ text err ]

                    Nothing ->
                        text ""
                ]
            ]
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    div
        [ css
            [ displayFlex
            , justifyContent spaceBetween
            , alignItems center
            , marginBottom Styles.spacing.lg
            ]
        ]
        [ h1
            [ css
                [ Css.fontSize Styles.fontSize.h1
                , fontWeight Styles.fontWeight.semibold
                , color Styles.colors.textPrimary
                ]
            ]
            [ text "PDF Models" ]
        , div [ css [ displayFlex, property "gap" "12px" ] ]
            [ a
                [ href (routeToPath Jobs)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.md
                    , border3 (px 1) solid Styles.colors.border
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , fontFamilies Styles.fontStack
                    , Css.fontSize Styles.fontSize.body
                    , hover [ backgroundColor Styles.colors.hover ]
                    ]
                ]
                [ text "Jobs" ]
            , Button.button Button.Secondary "Logout" SignOutClicked
            ]
        ]


viewModelSelector : PdfModel -> Html Msg
viewModelSelector currentPdfModel =
    div
        [ css
            [ marginBottom Styles.spacing.lg
            ]
        ]
        [ label
            [ css
                [ display block
                , Css.fontSize Styles.fontSize.body
                , color Styles.colors.textSecondary
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "Model" ]
        , select
            [ onInput (stringToPdfModel >> Maybe.withDefault defaultPdfModel >> ModelSelected)
            , value (pdfModelToString currentPdfModel)
            , css
                [ Css.width (pct 100)
                , padding2 Styles.spacing.sm Styles.spacing.md
                , backgroundColor Styles.colors.surface
                , border3 (px 1) solid Styles.colors.border
                , color Styles.colors.textPrimary
                , fontFamilies Styles.fontStack
                , Css.fontSize Styles.fontSize.body
                , cursor pointer
                , focus
                    [ borderColor Styles.colors.focus
                    , outline none
                    ]
                ]
            ]
            (List.map (viewModelOption currentPdfModel) allPdfModels)
        ]


viewModelOption : PdfModel -> PdfModel -> Html Msg
viewModelOption currentPdfModel pdfModel =
    option
        [ value (pdfModelToString pdfModel)
        , selected (pdfModel == currentPdfModel)
        ]
        [ text (pdfModelToDisplayName pdfModel) ]


viewModelInfo : PdfModel -> Bool -> Html Msg
viewModelInfo pdfModel isExpanded =
    let
        metadata =
            modelMetadata pdfModel

        arrow =
            if isExpanded then
                "▼ "

            else
                "▶ "
    in
    div
        [ css
            [ marginBottom Styles.spacing.lg
            ]
        ]
        [ -- Clickable header
          div
            [ onClick ToggleModelInfo
            , css
                [ cursor pointer
                , color Styles.colors.textSecondary
                , Css.fontSize Styles.fontSize.small
                , hover [ color Styles.colors.textPrimary ]
                ]
            ]
            [ text (arrow ++ "About this model") ]

        -- Expandable content
        , if isExpanded then
            div
                [ css
                    [ marginTop Styles.spacing.sm
                    , padding Styles.spacing.md
                    , backgroundColor Styles.colors.hover
                    , border3 (px 1) solid Styles.colors.border
                    , property "border-radius" "4px"
                    ]
                ]
                [ -- Model name and producer
                  div
                    [ css
                        [ fontWeight Styles.fontWeight.semibold
                        , color Styles.colors.textPrimary
                        , marginBottom (px 4)
                        ]
                    ]
                    [ text (pdfModelToDisplayName pdfModel ++ " by " ++ metadata.producer) ]

                -- Description
                , div
                    [ css
                        [ Css.fontSize Styles.fontSize.small
                        , color Styles.colors.textSecondary
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    [ text metadata.description ]

                -- Links
                , div
                    [ css
                        [ displayFlex
                        , property "gap" "16px"
                        ]
                    ]
                    (List.filterMap identity
                        [ metadata.githubUrl
                            |> Maybe.map
                                (\url ->
                                    a
                                        [ href url
                                        , Attr.target "_blank"
                                        , css
                                            [ color Styles.colors.accentPrimary
                                            , Css.fontSize Styles.fontSize.small
                                            , textDecoration none
                                            , hover [ textDecoration underline ]
                                            ]
                                        ]
                                        [ text "GitHub" ]
                                )
                        , metadata.huggingFaceUrl
                            |> Maybe.map
                                (\url ->
                                    a
                                        [ href url
                                        , Attr.target "_blank"
                                        , css
                                            [ color Styles.colors.accentPrimary
                                            , Css.fontSize Styles.fontSize.small
                                            , textDecoration none
                                            , hover [ textDecoration underline ]
                                            ]
                                        ]
                                        [ text "Hugging Face" ]
                                )
                        , metadata.docsUrl
                            |> Maybe.map
                                (\url ->
                                    a
                                        [ href url
                                        , Attr.target "_blank"
                                        , css
                                            [ color Styles.colors.accentPrimary
                                            , Css.fontSize Styles.fontSize.small
                                            , textDecoration none
                                            , hover [ textDecoration underline ]
                                            ]
                                        ]
                                        [ text "Docs" ]
                                )
                        , metadata.arxivUrl
                            |> Maybe.map
                                (\url ->
                                    a
                                        [ href url
                                        , Attr.target "_blank"
                                        , css
                                            [ color Styles.colors.accentPrimary
                                            , Css.fontSize Styles.fontSize.small
                                            , textDecoration none
                                            , hover [ textDecoration underline ]
                                            ]
                                        ]
                                        [ text "arXiv" ]
                                )
                        ]
                    )
                ]

          else
            text ""
        ]


viewPromptInput : PdfModel -> UploadState -> Html Msg
viewPromptInput pdfModel uploadState =
    if modelSupportsPrompt pdfModel then
        div
            [ css
                [ marginBottom Styles.spacing.lg
                ]
            ]
            [ label
                [ css
                    [ display block
                    , Css.fontSize Styles.fontSize.body
                    , color Styles.colors.textSecondary
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "Custom Prompt (Optional)" ]
            , textarea
                [ onInput PromptChanged
                , value uploadState.prompt
                , placeholder "Enter custom instructions for the model..."
                , css
                    [ Css.width (pct 100)
                    , padding2 Styles.spacing.sm Styles.spacing.md
                    , backgroundColor Styles.colors.surface
                    , border3 (px 1) solid Styles.colors.border
                    , color Styles.colors.textPrimary
                    , fontFamilies Styles.fontStack
                    , Css.fontSize Styles.fontSize.body
                    , Css.minHeight (px 80)
                    , resize vertical
                    , focus
                        [ borderColor Styles.colors.focus
                        , outline none
                        ]
                    ]
                ]
                []
            , p
                [ css
                    [ Css.fontSize Styles.fontSize.small
                    , color Styles.colors.textSecondary
                    , marginTop (px 4)
                    ]
                ]
                [ text "Provide custom instructions to guide how the model processes this document." ]
            ]

    else
        text ""


viewFileInput : UploadState -> Html Msg
viewFileInput uploadState =
    div []
        [ label
            [ for "file-input"
            , css
                [ display inlineBlock
                , padding2 Styles.spacing.sm Styles.spacing.md
                , border3 (px 1) solid Styles.colors.accentPrimary
                , color Styles.colors.accentPrimary
                , cursor pointer
                , fontFamilies Styles.fontStack
                , Css.fontSize Styles.fontSize.body
                , hover
                    [ backgroundColor Styles.colors.hover
                    ]
                ]
            ]
            [ text "Browse Files" ]
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


viewSelectedFile : File.File -> UploadState -> Html Msg
viewSelectedFile file uploadState =
    div
        [ css
            [ marginTop Styles.spacing.md
            , paddingTop Styles.spacing.md
            , borderTop3 (px 1) solid Styles.colors.border
            ]
        ]
        [ div
            [ css
                [ Css.fontSize Styles.fontSize.body
                , color Styles.colors.textSecondary
                , marginBottom Styles.spacing.xs
                ]
            ]
            [ text "Selected file:" ]
        , div
            [ css
                [ Css.fontSize Styles.fontSize.body
                , color Styles.colors.textPrimary
                , fontWeight Styles.fontWeight.semibold
                ]
            ]
            [ text (File.name file) ]
        , case uploadState.uploadProgress of
            Just progress ->
                div
                    [ css
                        [ marginTop Styles.spacing.sm
                        , color Styles.colors.accentWarning
                        ]
                    ]
                    [ text ("Uploading... " ++ String.fromInt (Basics.round (progress * 100)) ++ "%") ]

            Nothing ->
                if uploadState.submitting then
                    div
                        [ css
                            [ marginTop Styles.spacing.sm
                            , color Styles.colors.accentSuccess
                            ]
                        ]
                        [ text "Submitting job..." ]

                else
                    text ""
        ]


fileDecoder : Decode.Decoder File.File
fileDecoder =
    Decode.at [ "target", "files", "0" ] File.decoder
