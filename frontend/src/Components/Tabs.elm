module Components.Tabs exposing
    ( TabConfig
    , tabs
    )

{-| Tabs component matching Pencil design

  - Tabs container (k0LmA): bottom border=$--border, fit-content
  - Tab/Active (w7fzo): padding=[12,20], bottom border=2px $--primary
  - Tab/Default (Sj5z1): padding=[12,20], no bottom border

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Html.Styled.Events exposing (onClick)
import Styles


type alias TabConfig msg =
    { label : String
    , value : String
    , isActive : Bool
    , onSelect : msg
    }


{-| Tabs component with multiple tab options

    tabs
        [ { label = "Tab 1", value = "tab1", isActive = True, onSelect = SelectTab "tab1" }
        , { label = "Tab 2", value = "tab2", isActive = False, onSelect = SelectTab "tab2" }
        ]

-}
tabs : List (TabConfig msg) -> Html msg
tabs tabConfigs =
    div
        [ css tabsContainerStyles
        ]
        (List.map tabView tabConfigs)


{-| Render a single tab
-}
tabView : TabConfig msg -> Html msg
tabView config =
    button
        [ css (tabStyles config.isActive)
        , onClick config.onSelect
        , Html.Styled.Attributes.type_ "button"
        ]
        [ text config.label ]


{-| Tabs container styles - bottom border
-}
tabsContainerStyles : List Style
tabsContainerStyles =
    [ displayFlex
    , alignItems center
    , Css.height auto
    , Css.width auto
    , borderBottom3 (px 1) solid Styles.colors.border
    ]


{-| Tab styles - active vs default
-}
tabStyles : Bool -> List Style
tabStyles isActive =
    let
        baseStyles =
            [ displayFlex
            , alignItems center
            , justifyContent center
            , padding2 (px 12) (px 20)
            , backgroundColor transparent
            , border zero
            , borderBottom3 (px 2) solid transparent
            , outline none
            , cursor pointer
            , fontFamilies Styles.fontStack
            , Css.fontSize (px 13)
            , fontWeight (int 500)
            , lineHeight (num 1.5)
            , Styles.transitions.base
            , position relative
            , top (px 1) -- Offset to overlap the container border
            ]

        variantStyles =
            if isActive then
                [ color Styles.colors.foreground
                , borderBottomColor Styles.colors.primary
                ]

            else
                [ color Styles.colors.foregroundSubtle
                , hover
                    [ color Styles.colors.foreground
                    ]
                ]
    in
    baseStyles ++ variantStyles
