@file-handling
Feature: Open 3D Model Files
  As a user
  I want to open 3D model files in various formats
  So that I can view and analyze them

  Background:
    Given the application is running

  @stl @binary
  Scenario: Open binary STL file
    When I open a binary STL file
    Then the 3D model should be displayed
    And the file should be added to recent files
    And the model information panel should show the triangle count
    And the model should be auto-framed in the view

  @stl @ascii
  Scenario: Open ASCII STL file
    When I open an ASCII STL file
    Then the 3D model should be displayed
    And the file should be added to recent files
    And the model information panel should show the triangle count

  @3mf
  Scenario: Open 3MF file
    When I open a 3MF file
    Then the 3D model should be displayed
    And the file should be added to recent files
    And if the file contains multiple plates, the plate selector should appear

  @3mf @multi-plate
  Scenario: Open 3MF file with multiple plates
    Given I have a 3MF file with multiple plates
    When I open the 3MF file
    Then the first plate should be displayed
    And the plate selector panel should show all available plates
    And each plate button should display the plate name

  @openscad
  Scenario: Open OpenSCAD file
    Given OpenSCAD is installed on the system
    When I open an OpenSCAD file
    Then the file should be rendered to STL via OpenSCAD
    And the resulting 3D model should be displayed
    And the file should be added to recent files

  @openscad @missing
  Scenario: Open OpenSCAD file without OpenSCAD installed
    Given OpenSCAD is not installed on the system
    When I open an OpenSCAD file
    Then an error message should be displayed
    And the error should include installation instructions

  @openscad @empty
  Scenario: Open OpenSCAD file that produces empty geometry
    Given OpenSCAD is installed on the system
    When I open an OpenSCAD file that produces no geometry
    Then an empty file overlay should be displayed
    And the overlay should show an explanatory message

  @openscad @error
  Scenario: Open OpenSCAD file with render error
    Given OpenSCAD is installed on the system
    When I open an OpenSCAD file that has syntax errors
    Then an error overlay should be displayed
    And the error should show the OpenSCAD stdout/stderr output

  @go3mf
  Scenario: Open go3mf YAML configuration file
    Given go3mf CLI tool is installed on the system
    When I open a go3mf YAML configuration file
    Then the file should be rendered to 3MF via go3mf CLI
    And the resulting 3MF file should be loaded
    And if the 3MF contains multiple plates, the plate selector should appear
    And the file should be added to recent files

  @go3mf @missing
  Scenario: Open go3mf YAML file without go3mf installed
    Given go3mf CLI tool is not installed on the system
    When I open a go3mf YAML configuration file
    Then an error message should be displayed
    And the error should include search path hints

  @dialog
  Scenario: Open file using file dialog
    When I press Cmd+O
    Then a file open dialog should appear
    And the dialog should show supported file types
    When I select a valid 3D model file
    Then the file should be loaded and displayed

  @command-line
  Scenario: Open file from command line
    When I launch the application with a file path argument
    Then the specified file should be loaded automatically
    And the 3D model should be displayed

  @auto-frame
  Scenario: Auto-frame model on load
    When I open any 3D model file
    Then the camera should automatically frame the model
    And the entire model should be visible in the viewport
    And the camera distance should be calculated based on bounding box diagonal
    And a 1.5x safety factor should ensure full model visibility

  @drag-and-drop
  Scenario: Open file via drag and drop
    When I drag a supported file onto the application window
    Then the file should be loaded and displayed
    And the file should be added to recent files
    And the window title should update to show the file name

  @drag-and-drop
  Scenario Outline: Drag and drop supported file types
    When I drag a <file_type> file onto the application window
    Then the file should be loaded successfully

    Examples:
      | file_type |
      | .stl      |
      | .3mf      |
      | .scad     |
      | .yaml     |
      | .yml      |

  @drag-and-drop @intellij
  Scenario: Drag file from IntelliJ
    Given a file is open in IntelliJ IDEA
    When I drag the file from IntelliJ's project tree onto the application window
    Then the file should be loaded successfully
    And the legacy NSFilenamesPboardType should be handled correctly

  @drag-and-drop
  Scenario: Reject unsupported file type on drag
    When I drag an unsupported file type onto the application window
    Then the drag cursor should indicate the file cannot be dropped
    And no file should be loaded
