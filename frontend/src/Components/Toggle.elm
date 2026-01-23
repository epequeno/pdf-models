module Components.Toggle exposing (toggle)

{-| Toggle switch component matching Pencil design (2W4z1/t7zBN)

  - Off: border fill, knob on left
  - On: primary fill, knob on right
  - width=44px, height=24px
  - knob=20x20, cornerRadius=10
  - container cornerRadius=12

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, type_)
import Html.Styled.Events exposing (onCheck)
import Styles


{-| Toggle switch

    toggle model.isEnabled ToggleSwitched

-}
toggle : Bool -> (Bool -> msg) -> Html msg
toggle isOn onToggleMsg =
    label
        [ css containerStyles
        ]
        [ input
            [ type_ "checkbox"
            , Html.Styled.Attributes.checked isOn
            , onCheck onToggleMsg
            , css hiddenCheckboxStyles
            ]
            []
        , div
            [ css (trackStyles isOn)
            ]
            [ div
                [ css (knobStyles isOn)
                ]
                []
            ]
        ]


{-| Container styles
-}
containerStyles : List Style
containerStyles =
    [ displayFlex
    , alignItems center
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


{-| Toggle track styles
-}
trackStyles : Bool -> List Style
trackStyles isOn =
    let
        baseStyles =
            [ Css.width (px 44)
            , Css.height (px 24)
            , borderRadius (px 12)
            , padding (px 2)
            , displayFlex
            , alignItems center
            , Styles.transitions.base
            ]

        variantStyles =
            if isOn then
                [ backgroundColor Styles.colors.primary
                , justifyContent flexEnd
                ]

            else
                [ backgroundColor Styles.colors.border
                , justifyContent flexStart
                ]
    in
    baseStyles ++ variantStyles


{-| Toggle knob styles
-}
knobStyles : Bool -> List Style
knobStyles isOn =
    [ Css.width (px 20)
    , Css.height (px 20)
    , borderRadius (px 10)
    , backgroundColor
        (if isOn then
            Styles.colors.primaryForeground

         else
            Styles.colors.foreground
        )
    , Styles.transitions.base
    ]
