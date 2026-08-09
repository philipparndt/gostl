@camera @navigation
Feature: Camera Navigation
  As a user
  I want to navigate the 3D view using mouse and keyboard controls
  So that I can examine the model from any angle

  Background:
    Given the application is running
    And a 3D model is loaded

  @mouse
  Scenario: Rotate camera with left-click drag
    When I left-click and drag on the viewport
    Then the camera should rotate around the model
    And the rotation should follow the drag direction
    And the rotation should be free orbital rotation

  @mouse
  Scenario: Pan camera with shift-click drag
    When I hold Shift and left-click and drag on the viewport
    Then the camera should pan horizontally and vertically
    And the model should appear to move in the drag direction

  @mouse
  Scenario: Pan camera with middle-mouse drag
    When I middle-click and drag on the viewport
    Then the camera should pan horizontally and vertically
    And the behavior should be identical to shift-click drag

  @mouse
  Scenario: Zoom with scroll wheel
    When I scroll the mouse wheel
    Then the camera should zoom in or out
    And scroll up should zoom in
    And scroll down should zoom out
    And the zoom sensitivity should be adjustable

  @zoom-limits
  Scenario: Zoom steps and limits follow the model's size
    Given a model is loaded and framed
    When I scroll the mouse wheel
    Then each step should change the distance by a fraction of the distance already travelled
    And a step should cover the same fraction of the view on a 1.5 m model as on a 20 mm one
    When I zoom out to the maximum extent
    Then the camera should stop at 20 times the fitted distance
    And the model should still be in front of the far clip plane
    When I zoom in to the maximum extent
    Then the camera should stop at a fiftieth of the fitted distance

  @zoom-limits
  Scenario: Camera distance clamping with nothing loaded
    Given no model has been framed
    Then the camera distance should stay between 1.0 and 1000.0 units
