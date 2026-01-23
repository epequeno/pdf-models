module Components.SearchInput exposing (Config, searchInput)

{-| SearchInput component matching Pencil design (dTmHX)

  - Search icon + text input
  - height=44px
  - padding=[0,16]
  - gap=12px between icon and text

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, placeholder, type_, value)
import Html.Styled.Events exposing (onInput)
import Styles


{-| Configuration for search input
-}
type alias Config msg =
    { placeholder : String
    , value : String
    , onInput : String -> msg
    }


{-| Search input with icon

    searchInput
        { placeholder = "Search..."
        , value = model.searchQuery
        , onInput = SearchQueryChanged
        }
        [] -- optional additional styles

-}
searchInput : Config msg -> List Style -> Html msg
searchInput config additionalStyles =
    div
        [ css (searchContainerStyles ++ additionalStyles)
        ]
        [ Icon.icon Icon.Search Icon.Medium Styles.colors.foregroundSubtle
        , Html.Styled.input
            [ type_ "text"
            , value config.value
            , onInput config.onInput
            , placeholder config.placeholder
            , css searchInputStyles
            ]
            []
        ]


{-| Container styles for search input
-}
searchContainerStyles : List Style
searchContainerStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "12px"
    , Css.height (px 44)
    , padding2 zero (px 16)
    , border3 (px 1) solid Styles.colors.border
    , borderRadius zero
    , backgroundColor transparent
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderEmphasis
        ]
    , focus
        [ borderColor Styles.colors.borderFocus
        ]
    , pseudoClass "focus-within"
        [ borderColor Styles.colors.borderFocus
        , Styles.focusRing
        ]
    ]


{-| Input field styles
-}
searchInputStyles : List Style
searchInputStyles =
    [ flex (int 1)
    , border zero
    , outline none
    , backgroundColor transparent
    , color Styles.colors.foreground
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , lineHeight (num 1.5)
    , padding zero
    , Css.pseudoElement "placeholder"
        [ color Styles.colors.foregroundSubtle
        ]
    ]
