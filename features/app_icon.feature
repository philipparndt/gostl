@ui @app-icon
Feature: Application Icon
  As a user
  I want GoSTL to have its own icon in the Dock and in Finder
  So that I can recognize the app without reading its name

  The mark is a faceted solid with its right half drawn as wireframe, echoing
  the app's wireframe display modes. It is rendered on the dark viewport ground
  in the mesh cream and the Z-axis blue, so the icon uses the same palette as
  the viewport itself.

  Background:
    Given GoSTL is installed

  Scenario: Icon in the Dock
    When the application is running
    Then the Dock should show the GoSTL icon
    And the icon should not be the generic executable placeholder

  Scenario: Icon in Finder
    When I look at GoSTL.app in Finder
    Then the app should display the GoSTL icon
    And the icon should be shown at every Finder view size

  Scenario: Simplified artwork at small sizes
    Given the icon is displayed at 16 or 32 pixels
    Then the wireframe half should be drawn as a single heavy outline
    And the facet seams of the solid half should be omitted
    So that the two-tone split remains legible

  Scenario: Full artwork at large sizes
    Given the icon is displayed at 128 pixels or larger
    Then the solid half should show its individual lit facets
    And the wireframe half should show the full edge lattice

  Scenario: Dock icon when running an unbundled development build
    Given the executable is launched directly rather than through GoSTL.app
    When the application finishes launching
    Then the Dock icon should be loaded from the resource bundle
    And it should match the icon shown for the installed app

  Scenario: Icon travels with a release
    Given a release archive has been built
    Then the resource bundle should contain AppIcon.icns
    And the installed GoSTL.app should carry the icon in Contents/Resources
    And the app's Info.plist should name it via CFBundleIconFile
