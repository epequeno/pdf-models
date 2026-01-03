module Components.Table exposing (Column, table)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles


type alias Column data msg =
    { header : String
    , view : data -> Html msg
    }


table : List (Column data msg) -> List data -> Html msg
table columns data =
    Html.Styled.table
        [ css
            [ width (pct 100)
            , borderCollapse collapse
            , Css.fontSize Styles.fontSize.body
            , fontFamilies Styles.fontStack
            ]
        ]
        [ thead []
            [ tr
                [ css
                    [ borderBottom3 (px 1) solid Styles.colors.border
                    ]
                ]
                (List.map viewHeaderCell columns)
            ]
        , tbody []
            (List.map (viewRow columns) data)
        ]


viewHeaderCell : Column data msg -> Html msg
viewHeaderCell column =
    th
        [ css
            [ textAlign left
            , padding Styles.spacing.sm
            , color Styles.colors.textSecondary
            , fontWeight Styles.fontWeight.semibold
            ]
        ]
        [ text column.header ]


viewRow : List (Column data msg) -> data -> Html msg
viewRow columns rowData =
    tr
        [ css
            [ borderBottom3 (px 1) solid Styles.colors.border
            , hover
                [ backgroundColor Styles.colors.hover
                ]
            ]
        ]
        (List.map (\col -> viewCell col rowData) columns)


viewCell : Column data msg -> data -> Html msg
viewCell column rowData =
    td
        [ css
            [ padding Styles.spacing.sm
            , color Styles.colors.textPrimary
            ]
        ]
        [ column.view rowData ]
