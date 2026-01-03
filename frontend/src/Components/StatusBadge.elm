module Components.StatusBadge exposing (statusBadge)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles
import Types exposing (JobStatus(..))


statusBadge : JobStatus -> Html msg
statusBadge status =
    let
        ( statusColor, statusText ) =
            case status of
                Pending ->
                    ( Styles.colors.accentWarning, "pending" )

                Processing ->
                    ( Styles.colors.accentWarning, "processing" )

                Complete ->
                    ( Styles.colors.accentSuccess, "complete" )

                Failed ->
                    ( Styles.colors.accentError, "failed" )
    in
    span
        [ css
            [ color statusColor
            , Css.fontSize Styles.fontSize.body
            , fontFamilies Styles.fontStack
            ]
        ]
        [ span
            [ css
                [ marginRight (px 6)
                , fontWeight bold
                ]
            ]
            [ text "●" ]
        , text statusText
        ]
