@measurement @selection
Feature: Measurement Selection and Management
  As a user
  I want to select and manage measurements
  So that I can modify or delete specific measurements

  Background:
    Given the application is running
    And a 3D model is loaded
    And I have created multiple measurements

  Scenario: Rectangle selection with Option+drag
    When I hold Option and click and drag on the viewport
    Then a selection rectangle should appear
    And all measurements within the rectangle should be selected
    And selected measurements should be visually highlighted

  Scenario: Click to select measurement
    When I click on a measurement label
    Then the measurement should be selected
    And it should be visually highlighted

  Scenario: Click empty area to deselect
    Given one or more measurements are selected
    When I click on an empty area of the viewport
    Then all measurements should be deselected

  Scenario: Delete selected measurements
    Given one or more measurements are selected
    When I press Backspace or Delete
    Then the selected measurements should be removed
    And the remaining measurements should be preserved

  Scenario: Clear all measurements
    When I press Cmd+Shift+K
    Then all measurements should be removed
    And if a measurement is in progress, it should be cancelled

  Scenario: Clear measurements from menu
    When I select "Clear All Measurements" from the Tools menu
    Then all measurements should be removed

  Scenario: Measurement label positioning
    Given I have created a measurement
    Then the label should be positioned at the measurement point
    And the label should be rendered as 2D text over the 3D model
    And the label should use screen-space coordinates

  Scenario: Measurement color coding
    Given I have created different types of measurements
    Then each measurement type should have a distinct color
    And this helps distinguish between distance, angle, and radius measurements
