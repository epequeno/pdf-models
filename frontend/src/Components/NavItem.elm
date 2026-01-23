module Components.NavItem exposing
    ( navItem
    , navItemActive
    )

{-| Navigation Item component matching Pencil design

  - Active (IC0BW): fill=$--active-bg, left border=2px $--primary, text=$--foreground
  - Default (4MP5U): text=$--foreground-subtle
  - padding=[14,16]
  - gap=14px
  - icon=18x18

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Styles


{-| Default navigation item (inactive state)

    navItem Icon.Upload "Upload" "/upload"

-}
navItem : Icon.Icon -> String -> String -> Html msg
navItem icon label url =
    a
        [ href url
        , css navItemDefaultStyles
        ]
        [ Icon.icon icon Icon.MediumLarge Styles.colors.foregroundSubtle
        , span [ css (navItemLabelStyles False) ]
            [ text label ]
        ]


{-| Active navigation item

    navItemActive Icon.Upload "Upload" "/upload"

-}
navItemActive : Icon.Icon -> String -> String -> Html msg
navItemActive icon label url =
    a
        [ href url
        , css navItemActiveStyles
        ]
        [ Icon.icon icon Icon.MediumLarge Styles.colors.primary
        , span [ css (navItemLabelStyles True) ]
            [ text label ]
        ]


{-| Default nav item styles
-}
navItemDefaultStyles : List Style
navItemDefaultStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "14px"
    , padding2 (px 14) (px 16)
    , Css.width (pct 100)
    , backgroundColor transparent
    , color Styles.colors.foregroundSubtle
    , textDecoration none
    , Styles.transitions.base
    , hover
        [ backgroundColor Styles.colors.activeBg
        , color Styles.colors.foreground
        ]
    ]


{-| Active nav item styles - fill=$--active-bg, left border
-}
navItemActiveStyles : List Style
navItemActiveStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "14px"
    , padding2 (px 14) (px 16)
    , Css.width (pct 100)
    , backgroundColor Styles.colors.activeBg
    , color Styles.colors.foreground
    , textDecoration none
    , borderLeft3 (px 2) solid Styles.colors.primary
    , Styles.transitions.base
    ]


{-| Nav item label styles
-}
navItemLabelStyles : Bool -> List Style
navItemLabelStyles isActive =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 500)
    , lineHeight (num 1.5)
    , color
        (if isActive then
            Styles.colors.foreground

         else
            Styles.colors.foregroundSubtle
        )
    ]
