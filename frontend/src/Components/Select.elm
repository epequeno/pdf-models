module Components.Select exposing
    ( SelectConfig
    , select
    )

{-| Select dropdown component matching Pencil design (SVXMC)

  - Label + dropdown field
  - height=44px
  - padding=[0,16]
  - chevron-down icon

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, value)
import Html.Styled.Events exposing (onInput)
import Styles


type alias SelectConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , options : List ( String, String ) -- (value, label)
    , placeholder : String
    }


{-| Select dropdown with label

    select
        { label = "Choose option"
        , value = model.selectedOption
        , onInput = OptionSelected
        , options = [ ( "1", "Option 1" ), ( "2", "Option 2" ) ]
        , placeholder = "Choose..."
        }

-}
select : SelectConfig msg -> Html msg
select config =
    div [ css [ property "gap" "8px", display block ] ]
        [ label
            [ css labelStyles ]
            [ text config.label ]
        , div
            [ css selectContainerStyles
            ]
            [ Html.Styled.select
                [ value config.value
                , onInput config.onInput
                , css selectFieldStyles
                ]
                (option
                    [ value "", Html.Styled.Attributes.disabled True ]
                    [ text config.placeholder ]
                    :: List.map optionView config.options
                )
            , div [ css iconContainerStyles ]
                [ Icon.icon Icon.ChevronDown Icon.Medium Styles.colors.foregroundSubtle ]
            ]
        ]


{-| Render a single option
-}
optionView : ( String, String ) -> Html msg
optionView ( val, label ) =
    option [ value val ] [ text label ]


{-| Label styles
-}
labelStyles : List Style
labelStyles =
    [ display block
    , marginBottom (px 0)
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 12)
    , fontWeight (int 500)
    , color Styles.colors.foregroundMuted
    ]


{-| Select container (to position the chevron icon)
-}
selectContainerStyles : List Style
selectContainerStyles =
    [ position relative
    , displayFlex
    , alignItems center
    ]


{-| Select field styles
-}
selectFieldStyles : List Style
selectFieldStyles =
    [ width (pct 100)
    , Css.height (px 44)
    , padding2 zero (px 16)
    , paddingRight (px 40) -- Make room for chevron icon
    , backgroundColor transparent
    , border3 (px 1) solid Styles.colors.border
    , borderRadius zero
    , color Styles.colors.foreground
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , lineHeight (num 1.5)
    , outline none
    , cursor pointer
    , property "appearance" "none"
    , property "-webkit-appearance" "none"
    , property "-moz-appearance" "none"
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderEmphasis
        ]
    , focus
        [ borderColor Styles.colors.borderFocus
        , Styles.focusRing
        ]
    ]


{-| Icon container (positioned absolutely)
-}
iconContainerStyles : List Style
iconContainerStyles =
    [ position absolute
    , Css.right (px 16)
    , pointerEvents none
    , displayFlex
    , alignItems center
    ]
