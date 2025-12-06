@internal @ray-casting
Feature: Ray Casting and Intersection Detection
  As an internal system component
  I want accurate ray casting
  So that point picking and measurements work correctly

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Mouse to 3D ray generation
    When the user clicks on the viewport
    Then a ray should be generated from the camera through the click point
    And the ray should use correct NDC (Normalized Device Coordinates) conversion

  Scenario: Triangle intersection detection
    Given a ray is generated from a mouse click
    When the ray is tested against triangles
    Then the Moller-Trumbore algorithm should be used
    And the closest intersecting triangle should be identified
    And the intersection point should be returned

  Scenario: Bounding box acceleration
    Given a ray is generated from a mouse click
    When testing for intersections
    Then triangles outside the ray's bounding box path should be quickly rejected
    And this improves performance for large models

  Scenario: Surface normal calculation
    Given a ray intersects a triangle
    When the intersection is detected
    Then the surface normal at the intersection point should be available
    And this enables proper constraint calculations

  Scenario: No intersection handling
    When a mouse click does not intersect any geometry
    Then no intersection point should be returned
    And the measurement system should handle this gracefully
