@window @ui
Feature: Window Management
  As a user
  I want to manage multiple windows and tabs
  So that I can work with multiple models simultaneously

  Background:
    Given the application is running

  Scenario: Multi-window support
    When I open multiple files
    Then each file can be displayed in its own window
    And windows can be organized in tabs

  Scenario: Tabbed interface
    When I have multiple files open
    Then I should see tabs for each file
    And clicking a tab should switch to that file

  Scenario: Per-window state
    When I have multiple windows open
    Then each window should maintain its own camera position
    And each window should maintain its own slicing state
    And each window should maintain its own wireframe mode

  Scenario: Window title
    When a file is loaded
    Then the window title should show the filename

  Scenario: Window state persistence
    Given I have windows open with specific positions
    When I restart the application
    Then the window state should be restored from "~/.config/gostl/open_windows.json"

  Scenario: Close window
    When I close a window
    And other windows remain open
    Then the application should continue running

  Scenario: Quit application
    When I press Ctrl+C
    Then the application should quit cleanly
    And all file handles should be released
