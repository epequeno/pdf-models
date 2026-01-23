module Components.Sidebar exposing (sidebar, SidebarConfig)

{-| Sidebar component matching Pencil design (zemze)

  - Width=280px
  - padding=[40,28]
  - fill=$--background-sidebar
  - right border
  - Top: Logo + nav items (gap=48)
  - Bottom: Upgrade card + account row (gap=24)

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Styles


type alias SidebarConfig msg =
    { navigationItems : List (Html msg)
    , showUpgradeCard : Bool
    , userName : String
    , userEmail : String
    , onSignOut : msg
    }


{-| Sidebar component

    sidebar
        { navigationItems = [ navItemActive Icon.Upload "Upload" "/upload", ... ]
        , showUpgradeCard = True
        , userName = "John Doe"
        , userEmail = "john@example.com"
        , onSignOut = SignOutClicked
        }

-}
sidebar : SidebarConfig msg -> Html msg
sidebar config =
    div
        [ css sidebarContainerStyles
        ]
        [ -- Top section: Logo + Nav
          div [ css sidebarTopStyles ]
            [ -- Logo
              div [ css logoStyles ]
                [ div [ css logoMarkStyles ] []
                , div [ css logoTextStyles ]
                    [ text "PDF Models" ]
                ]

            -- Navigation items
            , div [ css navContainerStyles ]
                config.navigationItems
            ]

        -- Bottom section: Upgrade card + Account
        , div [ css sidebarBottomStyles ]
            [ -- Upgrade card (if enabled)
              if config.showUpgradeCard then
                upgradeCard

              else
                text ""

            -- Account row
            , accountRow config.userName config.userEmail
            ]
        ]


{-| Upgrade card component
-}
upgradeCard : Html msg
upgradeCard =
    div [ css upgradeCardStyles ]
        [ div [ css upgradeHeaderStyles ]
            [ Icon.icon Icon.ShieldCheck Icon.Medium Styles.colors.primary
            , span [ css upgradeHeaderTextStyles ]
                [ text "Upgrade" ]
            ]
        , p [ css upgradeDescStyles ]
            [ text "Get unlimited processing and priority support." ]
        , button [ css upgradeButtonStyles ]
            [ text "Upgrade Now" ]
        ]


{-| Account row component
-}
accountRow : String -> String -> Html msg
accountRow userName userEmail =
    div [ css accountRowStyles ]
        [ -- Avatar
          div [ css accountAvatarStyles ]
            [ text (String.left 1 userName) ]

        -- User info
        , div [ css accountInfoStyles ]
            [ div [ css accountNameStyles ]
                [ text userName ]
            , div [ css accountEmailStyles ]
                [ text userEmail ]
            ]

        -- Chevron
        , Icon.icon Icon.ChevronRight Icon.Medium Styles.colors.foregroundSubtle
        ]


{-| Sidebar container styles
-}
sidebarContainerStyles : List Style
sidebarContainerStyles =
    [ displayFlex
    , flexDirection column
    , justifyContent spaceBetween
    , Css.width (px 280)
    , Css.height (vh 100)
    , padding2 (px 40) (px 28)
    , backgroundColor Styles.colors.backgroundSidebar
    , borderRight3 (px 1) solid Styles.colors.border
    , flexShrink (int 0)
    ]


{-| Top section styles
-}
sidebarTopStyles : List Style
sidebarTopStyles =
    [ displayFlex
    , flexDirection column
    , property "gap" "48px"
    ]


{-| Logo container styles
-}
logoStyles : List Style
logoStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "12px"
    ]


{-| Logo mark (square with border)
-}
logoMarkStyles : List Style
logoMarkStyles =
    [ Css.width (px 36)
    , Css.height (px 36)
    , border3 (px 1) solid Styles.colors.primary
    , borderRadius zero
    , flexShrink (int 0)
    ]


{-| Logo text styles
-}
logoTextStyles : List Style
logoTextStyles =
    [ fontFamilies Styles.displayFontStack
    , Css.fontSize (px 22)
    , fontWeight (int 400)
    , color Styles.colors.foreground
    , letterSpacing (px 1)
    , lineHeight (num 1.2)
    ]


{-| Navigation container styles
-}
navContainerStyles : List Style
navContainerStyles =
    [ displayFlex
    , flexDirection column
    , property "gap" "4px"
    ]


{-| Bottom section styles
-}
sidebarBottomStyles : List Style
sidebarBottomStyles =
    [ displayFlex
    , flexDirection column
    , property "gap" "24px"
    ]


{-| Upgrade card styles
-}
upgradeCardStyles : List Style
upgradeCardStyles =
    [ displayFlex
    , flexDirection column
    , property "gap" "16px"
    , padding (px 20)
    , border3 (px 1) solid Styles.colors.borderEmphasis
    , borderRadius zero
    ]


{-| Upgrade header styles
-}
upgradeHeaderStyles : List Style
upgradeHeaderStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "10px"
    ]


{-| Upgrade header text
-}
upgradeHeaderTextStyles : List Style
upgradeHeaderTextStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 600)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    ]


{-| Upgrade description styles
-}
upgradeDescStyles : List Style
upgradeDescStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 12)
    , fontWeight (int 400)
    , color Styles.colors.foregroundMuted
    , lineHeight (num 1.5)
    , margin zero
    ]


{-| Upgrade button styles
-}
upgradeButtonStyles : List Style
upgradeButtonStyles =
    [ displayFlex
    , alignItems center
    , justifyContent center
    , padding2 (px 12) zero
    , backgroundColor Styles.colors.primary
    , color Styles.colors.primaryForeground
    , border zero
    , borderRadius zero
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 13)
    , fontWeight (int 500)
    , cursor pointer
    , Styles.transitions.base
    , hover
        [ backgroundColor Styles.colors.accentHover
        ]
    ]


{-| Account row styles
-}
accountRowStyles : List Style
accountRowStyles =
    [ displayFlex
    , alignItems center
    , property "gap" "12px"
    , paddingTop (px 16)
    , borderTop3 (px 1) solid Styles.colors.border
    , cursor pointer
    , Styles.transitions.base
    , hover
        [ backgroundColor Styles.colors.activeBg
        ]
    ]


{-| Account avatar styles
-}
accountAvatarStyles : List Style
accountAvatarStyles =
    [ displayFlex
    , alignItems center
    , justifyContent center
    , Css.width (px 40)
    , Css.height (px 40)
    , border3 (px 1) solid Styles.colors.borderEmphasis
    , borderRadius zero
    , backgroundColor Styles.colors.activeBg
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 16)
    , fontWeight (int 600)
    , color Styles.colors.primary
    , flexShrink (int 0)
    , textTransform uppercase
    ]


{-| Account info container
-}
accountInfoStyles : List Style
accountInfoStyles =
    [ displayFlex
    , flexDirection column
    , property "gap" "2px"
    , flex (int 1)
    , overflow hidden
    ]


{-| Account name styles
-}
accountNameStyles : List Style
accountNameStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 500)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    , overflow hidden
    , textOverflow ellipsis
    , whiteSpace noWrap
    ]


{-| Account email styles
-}
accountEmailStyles : List Style
accountEmailStyles =
    [ fontFamilies Styles.fontStack
    , Css.fontSize (px 12)
    , fontWeight (int 400)
    , color Styles.colors.foregroundMuted
    , lineHeight (num 1.5)
    , overflow hidden
    , textOverflow ellipsis
    , whiteSpace noWrap
    ]
