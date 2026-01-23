module Components.Checkbox exposing (checkbox)

{-| Checkbox component matching Pencil design (ehwSb/s56ml)

  - Unchecked: 20x20 border box
  - Checked: filled with check icon
  - gap=12px between box and label
  - label fontSize=14

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, type_)
import Html.Styled.Events exposing (onCheck)
import Styles


{-| Checkbox with label

    checkbox "Checkbox label" model.isChecked CheckboxToggled

-}
checkbox : String -> Bool -> (Bool -> msg) -> Html msg
checkbox labelText isChecked onCheckMsg =
    label
        [ css containerStyles
        ]
        [ input
            [ type_ "checkbox"
            , Html.Styled.Attributes.checked isChecked
            , onCheck onCheckMsg
            , css hiddenCheckboxStyles
            ]
            []
        , div
            [ css (checkboxBoxStyles isChecked)
            ]
            [ if isChecked then
                Icon.icon Icon.Check Icon.Small Styles.colors.primaryForeground

              else
                text ""
            ]
        , span
            [ css labelStyles
            ]
            [ text labelText ]
        ]


{-| Container styles
-}
containerStyles : List Style
containerStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "12px"
    , cursor pointer
    ]


{-| Hide the native checkbox
-}
hiddenCheckboxStyles : List Style
hiddenCheckboxStyles =
    [ position absolute
    , opacity (int 0)
    , pointerEvents none
    ]


{-| Checkbox box styles
-}
checkboxBoxStyles : Bool -> List Style
checkboxBoxStyles isChecked =
    let
        baseStyles =
            [ Css.width (px 20)
            , Css.height (px 20)
            , displayFlex
            , alignItems center
            , justifyContent center
            , flexShrink (int 0)
            , Styles.transitions.base
            ]

        variantStyles =
            if isChecked then
                [ backgroundColor Styles.colors.primary
                , border zero
                ]

            else
                [ backgroundColor transparent
                , border3 (px 1) solid Styles.colors.borderEmphasis
                , hover
                    [ borderColor Styles.colors.borderFocus
                    ]
                ]
    in
    baseStyles ++ variantStyles


{-| Label text styles
-}
labelStyles : List Style
labelStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    ]
