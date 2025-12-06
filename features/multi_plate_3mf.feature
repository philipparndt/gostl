@3mf @multi-plate
Feature: 3MF Multi-Plate Support
  As a user
  I want to view and switch between multiple plates in a 3MF file
  So that I can examine each plate's contents separately

  Background:
    Given the application is running

  Scenario: Plate selector appears for multi-plate files
    When I open a 3MF file containing multiple plates
    Then the plate selector panel should appear at the bottom-center
    And the panel should show all available plates as buttons
    And each button should display the plate name or number

  Scenario: First plate selected by default
    When I open a 3MF file containing multiple plates
    Then the first plate should be displayed
    And the first plate button should be highlighted

  Scenario: Switch between plates
    Given I have a 3MF file with multiple plates open
    When I click on a different plate button
    Then the selected plate's model should be displayed
    And the clicked button should become highlighted
    And the previous plate button should be de-highlighted

  Scenario: Per-plate properties
    Given I have a 3MF file with multiple plates open
    When I switch to a different plate
    Then the model information should update for the new plate
    And the triangle count should reflect the current plate
    And the dimensions should reflect the current plate

  Scenario: Camera reframe on plate switch
    Given I have a 3MF file with multiple plates open
    When I switch to a different plate
    Then the camera should automatically reframe to show the new plate's model

  Scenario: Slicing bounds reset on plate switch
    Given I have a 3MF file with multiple plates open
    And I have active slicing bounds
    When I switch to a different plate
    Then the slicing bounds should reset to the new plate's model bounds

  Scenario: Single plate file
    When I open a 3MF file containing only one plate
    Then the plate selector panel should not appear
    And the single plate's model should be displayed

  Scenario: Plate with custom colors
    Given I have a 3MF file with per-plate color information
    When I view a plate
    Then the model should be displayed with the plate's custom color
    And the material color should override the default

  Scenario: Plate metadata display
    Given I have a 3MF file with plate metadata
    When I view a plate
    Then the plate name should be shown in the plate button
    And object IDs should be associated with each plate
