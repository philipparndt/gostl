@integration @external-tools
Feature: External Tool Integration
  As a user
  I want to integrate with external tools
  So that I can extend the application's capabilities

  Background:
    Given the application is running

  @go3mf
  Scenario: Open file with go3mf
    Given a file is loaded
    When I press O
    Then the go3mf CLI tool should be launched
    And it should open with the current file
    And the command should be "go3mf build <file> --open"

  @go3mf
  Scenario: go3mf executable discovery
    When the application searches for go3mf
    Then it should check the following paths in order:
      | Path                      |
      | /usr/local/bin/go3mf      |
      | /opt/homebrew/bin/go3mf   |
      | ~/go/bin/go3mf            |
      | ~/.local/bin/go3mf        |
      | Shell PATH via 'which'    |

  @openscad
  Scenario: OpenSCAD executable discovery
    When the application searches for OpenSCAD
    Then it should check the following paths in order:
      | Path                                              |
      | /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD |
      | /usr/local/bin/openscad                            |
      | /opt/homebrew/bin/openscad                         |
      | Shell PATH via 'which'                             |

  @openscad
  Scenario: OpenSCAD rendering
    Given an OpenSCAD file is loaded
    Then it should be rendered to a temporary STL file
    And the temporary file should be in /var/tmp/
    And the temporary file should be cleaned up after use

  @openscad
  Scenario: OpenSCAD dependency tracking
    Given an OpenSCAD file with include statements is loaded
    Then all included files should be tracked
    And changes to any included file should trigger a reload

  @openscad
  Scenario: OpenSCAD messages panel
    Given an OpenSCAD file is rendered
    When the OpenSCAD output contains warnings, deprecations, or echo statements
    Then a collapsible messages panel should appear in the bottom-right corner
    And the panel should show the message count
    And the panel should be expandable to show individual messages

  @openscad
  Scenario: OpenSCAD warning display
    Given an OpenSCAD file produces a warning like "WARNING: Can't open library"
    Then the warning should appear with an orange triangle icon
    And the "WARNING:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD deprecation display
    Given an OpenSCAD file produces a deprecation like "DEPRECATED: Variable names..."
    Then the deprecation should appear with a yellow clock icon
    And the "DEPRECATED:" prefix should be stripped from the display

  @openscad
  Scenario: OpenSCAD echo display
    Given an OpenSCAD file uses echo() statements like "ECHO: -53.6289"
    Then the echo output should appear with a cyan speech bubble icon
    And the "ECHO:" prefix should be stripped from the display

  @go3mf
  Scenario: go3mf YAML rendering
    Given a go3mf YAML configuration file is loaded
    Then it should be rendered to a temporary 3MF file via go3mf CLI
    And the command should be "go3mf build <file> -o <output.3mf>"
    And the resulting 3MF should be parsed and displayed
    And the temporary file should be cleaned up on reload

  @go3mf @multi-plate
  Scenario: go3mf YAML with multiple plates
    Given a go3mf YAML configuration produces a multi-plate 3MF
    When the file is loaded
    Then the plate selector panel should appear
    And all plates from the generated 3MF should be available
