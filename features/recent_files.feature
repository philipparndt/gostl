@file-handling @recent-files
Feature: Recent Files Management
  As a user
  I want to access recently opened files
  So that I can quickly reopen models I've worked with

  Background:
    Given the application is running

  Scenario: Add file to recent files list
    When I open a 3D model file
    Then the file should be added to the top of the recent files list
    And the recent files list should persist across application restarts

  Scenario: Open file from recent files menu
    Given I have previously opened a 3D model file
    When I open the File menu
    And I navigate to the "Open Recent" submenu
    Then I should see the previously opened file
    When I click on the file entry
    Then the file should be loaded and displayed

  Scenario: Recent files list maintains order
    Given I have opened multiple files in sequence
    When I open the "Open Recent" submenu
    Then the most recently opened file should appear first
    And the files should be ordered by most recent first

  Scenario: Recent files list limit
    Given I have opened more than 10 files
    When I open the "Open Recent" submenu
    Then the list should show a maximum of 10 files
    And the oldest files should be removed from the list

  Scenario: Clear recent files menu
    Given I have files in the recent files list
    When I open the "Open Recent" submenu
    And I click "Clear Menu"
    Then all recent files should be removed from the list

  Scenario: Missing file cleanup
    Given I have a file in the recent files list
    And the file has been deleted from disk
    When I open the "Open Recent" submenu
    Then the missing file should be automatically removed from the list

  Scenario: Recent files persistence location
    When a file is added to recent files
    Then it should be stored in "~/.config/gostl/recent.json"
