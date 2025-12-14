@leveling @transformation
Feature: Level Object
  As a user
  I want to level objects by aligning two points
  So that my models are properly oriented for 3D printing

  Background:
    Given the application is running
    And a 3D model is loaded

  @menu
  Scenario: Start leveling from menu
    When I select Tools > Level Object
    Then leveling mode should be activated
    And the leveling panel should appear
    And the panel should show "Click to pick first point"

  @keyboard
  Scenario: Start leveling with keyboard
    When I press Cmd+L
    Then leveling mode should be activated
    And the leveling panel should appear

  @keyboard
  Scenario: Start leveling with L key
    When I press L
    Then leveling mode should be activated
    And the leveling panel should appear

  @point-selection
  Scenario: Select first point for leveling
    Given leveling mode is active
    When I click on a point on the model
    Then the first point should be marked
    And the panel should show "Click to pick second point"
    And the point indicator for point 1 should be filled

  @point-selection
  Scenario: Select second point for leveling
    Given leveling mode is active
    And the first point is already selected
    When I click on another point on the model
    Then the second point should be marked
    And the axis selection buttons (X, Y, Z) should appear
    And both point indicators should be filled

  @vertex-snapping
  Scenario: Point selection snaps to vertices
    Given leveling mode is active
    When I click near a vertex on the model
    Then the selected point should snap to the nearest vertex
    And the point coordinates should match the vertex position exactly

  @axis-selection
  Scenario: Apply leveling rotation on X axis
    Given two points are selected for leveling
    When I click the X axis button
    Then the model should rotate
    And both selected points should have the same X coordinate
    And leveling mode should be deactivated

  @axis-selection
  Scenario: Apply leveling rotation on Y axis
    Given two points are selected for leveling
    When I click the Y axis button
    Then the model should rotate
    And both selected points should have the same Y coordinate
    And leveling mode should be deactivated

  @axis-selection
  Scenario: Apply leveling rotation on Z axis
    Given two points are selected for leveling
    When I click the Z axis button
    Then the model should rotate
    And both selected points should have the same Z coordinate
    And leveling mode should be deactivated

  @undo
  Scenario: Undo leveling rotation
    Given I have applied a leveling rotation
    When I select Tools > Undo Leveling
    Then the model should return to its previous orientation
    And the undo option should become unavailable

  @cancel
  Scenario: Cancel leveling with ESC
    Given leveling mode is active
    When I press Escape
    Then leveling mode should be deactivated
    And no changes should be made to the model

  @cancel
  Scenario: Cancel leveling with panel button
    Given leveling mode is active
    When I click the cancel button in the panel
    Then leveling mode should be deactivated
    And no changes should be made to the model

  @edge-case
  Scenario: Points already level on selected axis
    Given two points are selected for leveling
    And both points already have the same Z coordinate
    When I click the Z axis button
    Then no rotation should be applied
    And a message should indicate the points are already level

  @edge-case
  Scenario: Leveling with very close points
    Given leveling mode is active
    When I select two points that are very close together
    Then the rotation should still be calculated correctly
    Or the system should indicate the points are too close
