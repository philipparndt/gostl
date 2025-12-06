@analysis
Feature: Model Analysis
  As a user
  I want accurate geometric analysis
  So that I can understand my model's properties

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Volume calculation
    When the model is analyzed
    Then the volume should be calculated using signed volume from triangle mesh
    And the volume should be displayed in appropriate units (mm³, cm³, or Liters)

  Scenario: Surface area calculation
    When the model is analyzed
    Then the surface area should be calculated as the sum of all triangle areas
    And the surface area should be displayed in mm² or cm²

  Scenario: Bounding box calculation
    When the model is analyzed
    Then the bounding box should be calculated
    And min/max coordinates should be available
    And dimensions (width, height, depth) should be derived

  Scenario: Center point calculation
    When the model is analyzed
    Then the center point should be calculated from bounding box
    And the center coordinates should be available for display

  Scenario: Triangle count
    When the model is analyzed
    Then the total triangle count should be available
    And it should be formatted with thousands separators for display

  Scenario: Edge extraction for wireframe
    When the model is analyzed
    Then all unique edges should be extracted
    And feature edges (sharp angles) should be identified
    And the edge data should be cached for wireframe rendering
