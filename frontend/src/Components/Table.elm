module Components.Table exposing
    ( Column
    , cell
    , headerCell
    , headerRow
    , row
    , table
    , tableFromColumns
    )

{-| Table components matching Pencil design

  - Table/Row (LGzSh): bottom border=$--border-subtle
  - Table/Cell (DqqhZ): padding=[16,20], fontSize=13, fontWeight=500
  - Table/HeaderRow (6Ks9E): bottom border=$--border-emphasis (thicker)
  - Table/HeaderCell (Ln12G): padding=[14,20], fontSize=11, fontWeight=600, text=$--primary

Usage (component-based):

    table []
        [ headerRow []
            [ headerCell [] [ text "Column 1" ]
            , headerCell [] [ text "Column 2" ]
            ]
        , row []
            [ cell [] [ text "Data 1" ]
            , cell [] [ text "Data 2" ]
            ]
        ]

Usage (column-based, backward compatible):

    tableFromColumns columns data

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles


{-| Column definition for column-based API (backward compatible)
-}
type alias Column data msg =
    { header : String
    , view : data -> Html msg
    }


{-| Table container
-}
table : List (Attribute msg) -> List (Html msg) -> Html msg
table attrs children =
    div
        (css tableContainerStyles :: attrs)
        children


{-| Table header row
-}
headerRow : List (Attribute msg) -> List (Html msg) -> Html msg
headerRow attrs children =
    div
        (css headerRowStyles :: attrs)
        children


{-| Table header cell
-}
headerCell : List (Attribute msg) -> List (Html msg) -> Html msg
headerCell attrs children =
    div
        (css headerCellStyles :: attrs)
        children


{-| Table body row
-}
row : List (Attribute msg) -> List (Html msg) -> Html msg
row attrs children =
    div
        (css rowStyles :: attrs)
        children


{-| Table body cell
-}
cell : List (Attribute msg) -> List (Html msg) -> Html msg
cell attrs children =
    div
        (css cellStyles :: attrs)
        children


{-| Column-based table (backward compatible with existing code)
-}
tableFromColumns : List (Column data msg) -> List data -> Html msg
tableFromColumns columns data =
    table []
        [ headerRow []
            (List.map (\col -> headerCell [] [ text col.header ]) columns)
        , div []
            (List.map (viewRowFromColumns columns) data)
        ]


{-| Render a row from column definitions
-}
viewRowFromColumns : List (Column data msg) -> data -> Html msg
viewRowFromColumns columns rowData =
    row []
        (List.map (\col -> cell [] [ col.view rowData ]) columns)


{-| Table container styles
-}
tableContainerStyles : List Style
tableContainerStyles =
    [ displayFlex
    , flexDirection column
    , Css.width (pct 100)
    , border3 (px 1) solid Styles.colors.border
    , borderRadius zero
    , overflow hidden
    ]


{-| Header row styles - bottom border=$--border-emphasis
-}
headerRowStyles : List Style
headerRowStyles =
    [ displayFlex
    , alignItems center
    , Css.width (pct 100)
    , Css.height auto
    , borderBottom3 (px 1) solid Styles.colors.borderEmphasis
    , backgroundColor transparent
    ]


{-| Header cell styles
-}
headerCellStyles : List Style
headerCellStyles =
    [ displayFlex
    , alignItems center
    , flex (int 1)
    , padding2 (px 14) (px 20)
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 11)
    , fontWeight (int 600)
    , textTransform uppercase
    , letterSpacing (px 0.5)
    , color Styles.colors.primary
    , lineHeight (num 1.5)
    ]


{-| Body row styles - bottom border=$--border-subtle
-}
rowStyles : List Style
rowStyles =
    [ displayFlex
    , alignItems center
    , Css.width (pct 100)
    , Css.height auto
    , borderBottom3 (px 1) solid Styles.colors.borderSubtle
    , backgroundColor transparent
    , Styles.transitions.base
    , hover
        [ backgroundColor Styles.colors.activeBg
        ]
    , lastChild
        [ borderBottom zero
        ]
    ]


{-| Body cell styles
-}
cellStyles : List Style
cellStyles =
    [ displayFlex
    , alignItems center
    , flex (int 1)
    , padding2 (px 16) (px 20)
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 13)
    , fontWeight (int 500)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    ]
