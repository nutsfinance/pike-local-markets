import os
import json
import re

def consolidate_deployments(deployments_dir, output_dir):
    """
    Consolidates deployment data from JSON files, filters based on rules, and
    organizes addresses by network and ABIs by contract name.
    """
    all_addresses = {}
    all_abis = {}

    # Ensure output directories exist
    os.makedirs(output_dir, exist_ok=True)
    abi_dir = os.path.join(output_dir, "abi")  # Define abi directory inside output
    os.makedirs(abi_dir, exist_ok=True) # Create the abi dir

    # Function to extract contract name from filename
    def get_contract_name(filename):
        return filename.replace(".json", "")

    for chain_dir_name in os.listdir(deployments_dir):
      chain_dir_path = os.path.join(deployments_dir, chain_dir_name)
      if not os.path.isdir(chain_dir_path):
        continue
      
      chain_name = chain_dir_name  # 1. Save folder name as is
      print(f"Processing Chain: {chain_name}")
      
      for filename in os.listdir(chain_dir_path):
        if not filename.endswith(".json"):
          continue

        file_path = os.path.join(chain_dir_path, filename)

        contract_name = get_contract_name(filename)
        
        
        #Filter Module files
        if filename.lower().endswith("module.json"):
          print(f"  Skipping (Module): {filename}")
          continue
        
        is_proxy = filename.lower().endswith(".proxy.json") # 2. Check for ".proxy.json"

        # Filter files with additional suffixes
        if not is_proxy:
          name_without_ext = filename.lower().replace(".json", "")
          match = re.match(r"([a-z]+)(\.[a-z]+)+$", name_without_ext)
          if match:
            print(f"  Skipping (Additional Suffix): {filename}")
            continue

        # Handle Proxy preference
        if not is_proxy:
          proxy_file = filename.replace(".json", ".proxy.json") # 2. Check for ".proxy.json"
          if proxy_file in os.listdir(chain_dir_path):
             print(f"   Skipping (Proxy Exists): {filename}")
             continue

        print(f"  Processing: {filename}")
        try:
          with open(file_path, 'r') as f:
              data = json.load(f)
              address = data.get('address')
              abi = data.get('abi')
              if not address or not abi:
                  print(f"   Warning: missing address or abi in: {filename}")
                  continue

              #Store Addresses
              if chain_name not in all_addresses:
                all_addresses[chain_name] = {}
              all_addresses[chain_name][contract_name] = address
              # Store ABI, avoiding duplicate if already exists.
              # Store ABI as is with the full name
              all_abis[filename] = abi 


        except FileNotFoundError:
          print(f"   Error: File not found: {filename}")
        except json.JSONDecodeError:
          print(f"   Error: Invalid JSON format: {filename}")
        except Exception as e:
          print(f"   Error processing {filename}: {e}")


    # Write output
    with open(os.path.join(output_dir, "addresses.json"), 'w') as f:
        json.dump(all_addresses, f, indent=2)

    for name, abi in all_abis.items():
      with open(os.path.join(abi_dir, f"{name.replace('.json', '')}.abi.json"), 'w') as f: # 3. Save ABI in abi subdir
        json.dump(abi, f, indent=2)

    print("\nConsolidation complete.")
    return all_addresses, all_abis

def generate_readme(addresses, abis, output_dir):
    """Generates a README.md to document the consolidated data."""
    readme_path = os.path.join(output_dir, "README.md")
    with open(readme_path, 'w') as f:
      f.write("# Contract Deployment Data\n\n")
      f.write("This document summarizes the smart contract deployment information consolidated from the `deployments` folder.\n\n")

      f.write("## Contract Addresses by Network\n\n")
      for chain, contracts in addresses.items():
            f.write(f"### {chain.capitalize()}\n\n")
            f.write("| Contract Name | Address |\n")
            f.write("| --- | --- |\n")
            for name, address in contracts.items():
                f.write(f"| `{name}` | `{address}` |\n")
            f.write("\n")

      f.write("## Contract ABIs\n\n")
      f.write(f"ABI files can be found in the `{os.path.join(output_dir, 'abi')}` directory as `[ContractName].abi.json`.\n\n") # 3. Updated path to abi folder
      f.write("## Script Details \n\n")
      f.write("The original script reads all contracts files inside `deployments/` subfolders, based on each chain.\n")
      f.write("It is applied these filters: \n")
      f.write("- If a file ends in `.module.json` it ignores it.\n")
      f.write("- If it has proxy version with name `[ContractName].proxy.json` then only proxy version is taken.\n")
      f.write("- If it has another additional suffix like `[ContractName].suffix.json` then it is skipped.")
    print(f"README.md generated at: {readme_path}")

if __name__ == "__main__":
    deployments_dir = 'deployments'  # Path to your deployments folder
    output_dir = 'consolidated'  # Output directory for JSON data
    
    addresses, abis = consolidate_deployments(deployments_dir, output_dir)
    generate_readme(addresses, abis, output_dir)