module Components.Icon exposing
    ( Icon(..)
    , Size(..)
    , icon
    )

{-| Icon component using Lucide icons

This module provides a wrapper for Lucide icons (<https://lucide.dev/>)
Icons are rendered using the lucide icon font which should be included in index.html

Usage:
import Components.Icon as Icon

    Icon.icon Icon.Upload Icon.Medium colors.primary

-}

import Css exposing (..)
import Html.Styled exposing (Html, i)
import Html.Styled.Attributes exposing (attribute, css)


{-| Icon size options
-}
type Size
    = Small -- 14x14
    | Medium -- 16x16
    | MediumLarge -- 18x18
    | Large -- 24x24


{-| Available icons from Lucide
-}
type Icon
    = Plus
    | Filter
    | ArrowLeft
    | ArrowRight
    | Trash2
    | Search
    | Eye
    | Upload
    | Check
    | Home
    | File
    | Info
    | X
    | ChevronDown
    | ChevronRight
    | ChevronLeft
    | List
    | Layers
    | Settings
    | Briefcase
    | ShieldCheck
    | User
    | LogOut
    | Edit
    | MoreVertical
    | Download
    | RefreshCw
    | Bell
    | Send
    | FileText
    | Sliders
    | Calendar
    | Folder
    | Zap
    | Cpu
    | Columns
    | ArrowRightIcon
    | CheckCircle
    | Pencil
    | Play


{-| Convert Icon to lucide icon name
-}
iconName : Icon -> String
iconName iconType =
    case iconType of
        Plus ->
            "plus"

        Filter ->
            "filter"

        ArrowLeft ->
            "arrow-left"

        ArrowRight ->
            "arrow-right"

        Trash2 ->
            "trash-2"

        Search ->
            "search"

        Eye ->
            "eye"

        Upload ->
            "upload"

        Check ->
            "check"

        Home ->
            "home"

        File ->
            "file"

        Info ->
            "info"

        X ->
            "x"

        ChevronDown ->
            "chevron-down"

        ChevronRight ->
            "chevron-right"

        ChevronLeft ->
            "chevron-left"

        List ->
            "list"

        Layers ->
            "layers"

        Settings ->
            "settings"

        Briefcase ->
            "briefcase"

        ShieldCheck ->
            "shield-check"

        User ->
            "user"

        LogOut ->
            "log-out"

        Edit ->
            "edit"

        MoreVertical ->
            "more-vertical"

        Download ->
            "download"

        RefreshCw ->
            "refresh-cw"

        Bell ->
            "bell"

        Send ->
            "send"

        FileText ->
            "file-text"

        Sliders ->
            "sliders"

        Calendar ->
            "calendar"

        Folder ->
            "folder"

        Zap ->
            "zap"

        Cpu ->
            "cpu"

        Columns ->
            "columns"

        ArrowRightIcon ->
            "arrow-right"

        CheckCircle ->
            "check-circle"

        Pencil ->
            "pencil"

        Play ->
            "play"


{-| Convert size to pixel dimensions
-}
sizeToPixels : Size -> Int
sizeToPixels size =
    case size of
        Small ->
            14

        Medium ->
            16

        MediumLarge ->
            18

        Large ->
            24


{-| Render an icon

    Icon.icon Icon.Upload Icon.Large colors.primary

-}
icon : Icon -> Size -> Color -> Html msg
icon iconType size color =
    let
        pixels =
            sizeToPixels size

        iconClass =
            "lucide lucide-" ++ iconName iconType
    in
    i
        [ attribute "data-lucide" (iconName iconType)
        , css
            [ Css.width (px (toFloat pixels))
            , Css.height (px (toFloat pixels))
            , Css.color color
            , display inlineBlock
            , flexShrink (int 0)
            ]
        ]
        []
