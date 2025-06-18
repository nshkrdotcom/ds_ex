#!/usr/bin/env python3
"""
Script to convert explicit try blocks to implicit try in Elixir test files.
Converts 'try do' blocks to implicit try by removing 'try do' and moving rescue/catch/after to function level.
"""

import re
import os

def convert_try_blocks(file_path):
    """Convert explicit try blocks to implicit try in a file."""
    with open(file_path, 'r') as f:
        content = f.read()
    
    original_content = content
    
    # Pattern to match try do blocks with their rescue/catch/after clauses
    # This is a simplified pattern - we'll need to be careful with nested structures
    try_pattern = r'(\s+)try do\n(.*?)(\n\s+(?:rescue|catch|after).*?)(\n\s+end)'
    
    def replace_try_block(match):
        indent = match.group(1)
        try_body = match.group(2)
        rescue_clauses = match.group(3)
        end_clause = match.group(4)
        
        # Remove the try do and end, keep the body and rescue clauses
        # The rescue clauses should be moved to function level
        return try_body + rescue_clauses
    
    # Apply the conversion
    content = re.sub(try_pattern, replace_try_block, content, flags=re.DOTALL | re.MULTILINE)
    
    # Write back if changed
    if content != original_content:
        with open(file_path, 'w') as f:
            f.write(content)
        return True
    return False

def main():
    """Main function to process all test files."""
    test_files = [
        '/home/home/p/g/n/ds_ex/test/concurrent/concurrent_execution_test.exs',
        '/home/home/p/g/n/ds_ex/test/concurrent/client_stress_test.exs',
        '/home/home/p/g/n/ds_ex/test/concurrent/race_condition_test.exs',
        '/home/home/p/g/n/ds_ex/test/property/signature_data_property_test.exs',
        '/home/home/p/g/n/ds_ex/test/property/evaluation_metrics_property_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/telemetry_race_condition_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/mock_contamination_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/system_edge_cases_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/foundation_lifecycle_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/bootstrap_advanced_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/teleprompter/simba/strategy_test.exs',
        '/home/home/p/g/n/ds_ex/test/unit/teleprompter/simba_edge_cases_test.exs',
        '/home/home/p/g/n/ds_ex/test/integration/error_recovery_test.exs',
        '/home/home/p/g/n/ds_ex/test/integration/beacon_instruction_generation_test.exs',
        '/home/home/p/g/n/ds_ex/test/integration/simba_example_test.exs',
        '/home/home/p/g/n/ds_ex/test/integration/client_manager_integration_test.exs',
        '/home/home/p/g/n/ds_ex/test/integration/beacon_readiness_test.exs',
        '/home/home/p/g/n/ds_ex/test/performance/memory_performance_test.exs',
        '/home/home/p/g/n/ds_ex/test/support/test_helpers.exs'
    ]
    
    changed_files = []
    
    for file_path in test_files:
        if os.path.exists(file_path):
            if convert_try_blocks(file_path):
                changed_files.append(file_path)
    
    print(f"Converted {len(changed_files)} files:")
    for file_path in changed_files:
        print(f"  - {file_path}")

if __name__ == "__main__":
    main()