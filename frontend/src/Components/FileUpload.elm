module Components.FileUpload exposing (fileUpload)

{-| FileUpload component matching Pencil design (YJl0t)

  - width=480px
  - height=200px
  - centered vertical layout
  - upload icon (48x48)
  - border=$--border
  - gap=16px

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, for, id, type_)
import Html.Styled.Events exposing (on)
import Json.Decode as Decode
import Styles


{-| File upload component with drag and drop area

    fileUpload "file-input" FileSelected

-}
fileUpload : String -> (Decode.Value -> msg) -> Html msg
fileUpload inputId onFileMsg =
    label
        [ for inputId
        , css containerStyles
        ]
        [ -- Icon
          div [ css iconContainerStyles ]
            [ Icon.icon Icon.Upload Icon.Large Styles.colors.primary ]

        -- Text
        , div [ css textContainerStyles ]
            [ div [ css titleStyles ]
                [ text "Drag and drop your PDF here" ]
            , div [ css subtitleStyles ]
                [ text "or click to browse files" ]
            ]

        -- Hint
        , div [ css hintStyles ]
            [ text "PDF files only, max 50MB" ]

        -- Hidden input
        , input
            [ type_ "file"
            , id inputId
            , on "change" (Decode.map onFileMsg Decode.value)
            , css hiddenInputStyles
            ]
            []
        ]


{-| Container styles
-}
containerStyles : List Style
containerStyles =
    [ displayFlex
    , flexDirection column
    , alignItems center
    , justifyContent center
    , property "gap" "16px"
    , Css.width (px 480)
    , Css.height (px 200)
    , border3 (px 1) solid Styles.colors.border
    , borderRadius zero
    , cursor pointer
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderEmphasis
        , backgroundColor Styles.colors.activeBg
        ]
    ]


{-| Icon container - 48x48 border box with icon
-}
iconContainerStyles : List Style
iconContainerStyles =
    [ displayFlex
    , alignItems center
    , justifyContent center
    , Css.width (px 48)
    , Css.height (px 48)
    , border3 (px 1) solid Styles.colors.borderEmphasis
    , borderRadius zero
    ]


{-| Text container
-}
textContainerStyles : List Style
textContainerStyles =
    [ displayFlex
    , flexDirection column
    , alignItems center
    , property "gap" "4px"
    ]


{-| Title styles
-}
titleStyles : List Style
titleStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 500)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    ]


{-| Subtitle styles
-}
subtitleStyles : List Style
subtitleStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 12)
    , fontWeight (int 400)
    , color Styles.colors.foregroundSubtle
    , lineHeight (num 1.5)
    ]


{-| Hint styles
-}
hintStyles : List Style
hintStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 11)
    , fontWeight (int 400)
    , color Styles.colors.foregroundSubtle
    , lineHeight (num 1.5)
    ]


{-| Hidden file input
-}
hiddenInputStyles : List Style
hiddenInputStyles =
    [ position absolute
    , Css.width (px 1)
    , Css.height (px 1)
    , padding zero
    , margin (px -1)
    , overflow hidden
    , property "clip" "rect(0, 0, 0, 0)"
    , property "white-space" "nowrap"
    , borderWidth zero
    ]
