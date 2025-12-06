@measurement @distance
Feature: Distance Measurement
  As a user
  I want to measure distances on the model
  So that I can verify dimensions and spacing

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Start distance measurement mode
    When I press Cmd+D
    Then distance measurement mode should be activated
    And the cursor should indicate measurement mode is active

  Scenario: Add measurement points
    Given distance measurement mode is active
    When I click on the model surface
    Then a measurement point should be placed at the click location
    And I can continue clicking to add more points

  Scenario: Multi-point measurement
    Given distance measurement mode is active
    When I click multiple points on the model
    Then the distance between consecutive points should be displayed
    And each segment should show its individual distance

  Scenario: End measurement with X key
    Given distance measurement mode is active
    And I have placed at least 2 points
    When I press X
    Then the current measurement should be completed
    And I should exit measurement mode

  Scenario: Preview line
    Given distance measurement mode is active
    And I have placed at least one point
    When I move the mouse over the model
    Then a preview line should show where the next point would be
    And the preview distance should be displayed

  Scenario: Point picking precision
    Given distance measurement mode is active
    When I click near a vertex or edge
    Then the point should snap to the nearest model feature
    And this ensures precise measurements

  Scenario: Undo last point
    Given distance measurement mode is active
    And I have placed multiple points
    When I press Backspace
    Then the last point should be removed
    And the measurement should update accordingly

  @constraint
  Scenario: X-axis constraint
    Given distance measurement mode is active
    And I have placed at least one point
    When I press the X key
    Then movement should be constrained to the X axis
    And the next point should only move along X from the previous point

  @constraint
  Scenario: Y-axis constraint
    Given distance measurement mode is active
    And I have placed at least one point
    When I press the Y key
    Then movement should be constrained to the Y axis
    And the next point should only move along Y from the previous point

  @constraint
  Scenario: Z-axis constraint
    Given distance measurement mode is active
    And I have placed at least one point
    When I press the Z key
    Then movement should be constrained to the Z axis
    And the next point should only move along Z from the previous point

  @constraint
  Scenario: Direction constraint with Option key
    Given distance measurement mode is active
    And I have placed at least one point
    When I hold the Option key
    Then movement should be constrained to the direction towards the previous point

  @constraint
  Scenario: Release axis constraint
    Given distance measurement mode is active
    And an axis constraint is active
    When I press the Option key again
    Then the axis constraint should be released
    And I should return to free movement

  Scenario: Distance label display
    Given I have completed a distance measurement
    Then a label should be displayed at the measurement location
    And the label should show the distance value
    And the value should be formatted with appropriate precision
