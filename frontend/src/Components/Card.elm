module Components.Card exposing
    ( card
    , cardWithHeaderAndActions
    )

{-| Card component matching Pencil design (L7UUb)

Structure:

  - cardHeader: padding=24, title (Playfair Display 22px) + description (14px)
  - cardContent: padding=[0,24], vertical layout, gap=16
  - cardActions: padding=24, right-aligned, gap=12

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles


{-| Basic card with content only
-}
card : List (Html msg) -> Html msg
card content =
    div
        [ css cardStyles
        ]
        content


{-| Card with header (title + description), content, and action buttons
-}
cardWithHeaderAndActions :
    { title : String
    , description : String
    , content : List (Html msg)
    , actions : List (Html msg)
    }
    -> Html msg
cardWithHeaderAndActions config =
    div
        [ css cardStyles
        ]
        [ -- Header
          div [ css cardHeaderStyles ]
            [ h3
                [ css cardTitleStyles ]
                [ text config.title ]
            , p
                [ css cardDescriptionStyles ]
                [ text config.description ]
            ]

        -- Content
        , div [ css cardContentStyles ]
            config.content

        -- Actions
        , div [ css cardActionsStyles ]
            config.actions
        ]


{-| Card container styles - border=$--border, width=400px default
-}
cardStyles : List Style
cardStyles =
    [ backgroundColor transparent
    , border3 (px 1) solid Styles.colors.border
    , borderRadius zero
    , displayFlex
    , flexDirection column
    , Css.width (px 400)
    ]


{-| Card header styles - padding=24
-}
cardHeaderStyles : List Style
cardHeaderStyles =
    [ padding (px 24)
    , displayFlex
    , flexDirection column
    , property "gap" "4px"
    ]


{-| Card title styles - Playfair Display, 22px
-}
cardTitleStyles : List Style
cardTitleStyles =
    [ fontFamilies Styles.displayFontStack
    , Css.fontSize (px 22)
    , fontWeight (int 400)
    , lineHeight (num 1.2)
    , color Styles.colors.foreground
    , margin zero
    ]


{-| Card description styles - 14px, foreground-muted
-}
cardDescriptionStyles : List Style
cardDescriptionStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , lineHeight (num 1.5)
    , color Styles.colors.foregroundMuted
    , margin zero
    ]


{-| Card content styles - padding=[0,24], gap=16
-}
cardContentStyles : List Style
cardContentStyles =
    [ padding2 zero (px 24)
    , displayFlex
    , flexDirection column
    , property "gap" "16px"
    , Css.height auto
    ]


{-| Card actions styles - padding=24, right-aligned, gap=12
-}
cardActionsStyles : List Style
cardActionsStyles =
    [ padding (px 24)
    , displayFlex
    , justifyContent flexEnd
    , property "gap" "12px"
    , Css.height auto
    ]
