module Components.AppLayout exposing (Config, view)

{-| AppLayout - Main application layout with sidebar navigation

This component provides the standard authenticated page layout structure:

  - Sidebar navigation (280px fixed width)
  - Main content area (flexible width)

Based on Pencil design node: Upload (r1Bae) and other authenticated pages

-}

import Components.Icon as Icon
import Components.NavItem as NavItem
import Components.Sidebar as Sidebar
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Types exposing (Route(..))


{-| Layout configuration for different page types
-}
type alias Config msg =
    { currentRoute : Route
    , userName : String
    , userEmail : String
    , showUpgradeCard : Bool
    , isAdmin : Bool
    , onSignOut : msg
    }


{-| Main layout view with sidebar + content area
-}
view : Config msg -> List (Html msg) -> Html msg
view config content =
    div
        [ css
            [ displayFlex
            , height (vh 100)
            , backgroundColor (hex "0F0F0F") -- $--background
            , overflow hidden
            ]
        ]
        [ -- Sidebar
          Sidebar.sidebar
            { navigationItems = buildNavigationItems config.currentRoute config.isAdmin
            , showUpgradeCard = config.showUpgradeCard
            , userName = config.userName
            , userEmail = config.userEmail
            , onSignOut = config.onSignOut
            }

        -- Main content area
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , flex (int 1)
                , height (pct 100)
                , overflowY auto
                ]
            ]
            [ mainContent content
            ]
        ]


{-| Build navigation items based on current route and user role
-}
buildNavigationItems : Route -> Bool -> List (Html msg)
buildNavigationItems currentRoute isAdmin =
    let
        -- Main navigation items
        mainNav =
            [ navItemFor currentRoute Icon.Upload "Upload" (Upload Types.Docling)
            , navItemFor currentRoute Icon.List "Jobs" Jobs
            , navItemFor currentRoute Icon.Layers "Models" Models
            , navItemFor currentRoute Icon.Settings "Configurations" Configs
            ]

        -- Admin navigation items
        adminNav =
            if isAdmin then
                [ -- Admin section divider could go here
                  navItemFor currentRoute Icon.ShieldCheck "Admin Config" AdminConfigs
                ]

            else
                []
    in
    mainNav ++ adminNav


{-| Helper to create nav item (active or default based on current route)
-}
navItemFor : Route -> Icon.Icon -> String -> Route -> Html msg
navItemFor currentRoute icon label targetRoute =
    if routeMatches currentRoute targetRoute then
        NavItem.navItemActive icon label (Types.routeToPath targetRoute)

    else
        NavItem.navItem icon label (Types.routeToPath targetRoute)


{-| Check if two routes match (ignoring parameters)
-}
routeMatches : Route -> Route -> Bool
routeMatches current target =
    case ( current, target ) of
        ( Login, Login ) ->
            True

        ( SignUp, SignUp ) ->
            True

        ( Upload _, Upload _ ) ->
            True

        ( Jobs, Jobs ) ->
            True

        ( Models, Models ) ->
            True

        ( Configs, Configs ) ->
            True

        ( AdminConfigs, AdminConfigs ) ->
            True

        _ ->
            False


{-| Main content wrapper with standard padding and gap
Based on uploadMain (5KsNS) from Pencil design
-}
mainContent : List (Html msg) -> Html msg
mainContent content =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "32px"
            , padding2 (px 48) (px 56)
            , height (pct 100)
            , width (pct 100)
            ]
        ]
        content
