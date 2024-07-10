import pandas as pd

# Load the Excel file
file_path = 'output.xlsx'
xl = pd.ExcelFile(file_path)

# Remove leading and trailing whitespace from string elements
df = pd.read_excel(file_path, header=None)
df = df.applymap(lambda x: x.strip() if isinstance(x, str) else x)

# Function to find all rows that contain a specific substring
def find_rows_containing(df, substring):
    rows = []
    for i, row in df.iterrows():
        if any(isinstance(cell, str) and substring in cell for cell in row):
            rows.append(i)
    return rows

# Function to extract values from specific column in each sheet
def extract_values_from_sheets(xl):
    all_values = []
    for sheet_name in xl.sheet_names:
        df = xl.parse(sheet_name)
        header_rows = df.apply(lambda row: row.astype(str).str.contains("Analysis of Maximum Likelihood Estimates", case=False).any(), axis=1)
        header_indices = header_rows[header_rows].index.tolist()
        for idx in header_indices:
            start_row = idx + 4  # Start 4 rows below the header
            while True:
                try:
                    value = df.iloc[start_row, 7]  # Column H (index 7)
                    if pd.isna(value):
                        break
                    all_values.append(value)
                    start_row += 1
                except IndexError:
                    break
    return all_values

# Locate all start and end markers of the tables
start_rows = find_rows_containing(df, 'Odds Ratio Estimates')
end_rows = find_rows_containing(df, 'Association of Predicted Probabilities and Observed Responses')

# Ensure there are the same number of start and end markers
if len(start_rows) != len(end_rows):
    raise ValueError("Mismatch between number of start and end markers for tables.")

# Define the columns for the clean table
columns = ['Effect', 'Point Estimate', '95% Wald Confidence Limits']

# Create a DataFrame to store all clean tables
all_clean_tables = pd.DataFrame(columns=columns)

# Process each table
for start_row, end_row in zip(start_rows, end_rows):
    # Extract the table between these rows
    table = df.iloc[start_row + 1:end_row, :].reset_index(drop=True)

    # Create a list to store rows for the current table
    rows = []

    # Extract the necessary data from the table
    for i, row in table.iterrows():
        if pd.notna(row[0]):
            effect = row[1]
            point_estimate = row[2]
            lower_confidence_limit = row[3]
            upper_confidence_limit = row[4]

            # Concatenate '95% Wald Confidence Limits' and '95% Wald Confidence Limits.1' with a comma
            confidence_limits = f"{lower_confidence_limit}, {upper_confidence_limit}"

            # Append the row to the list of rows
            rows.append({
                'Effect': effect,
                'Point Estimate': point_estimate,
                '95% Wald Confidence Limits': confidence_limits
            })

    # Create a DataFrame for the current table and append to all_clean_tables
    clean_table = pd.DataFrame(rows, columns=columns)
    all_clean_tables = pd.concat([all_clean_tables, clean_table], ignore_index=True)

# Extract values from each sheet and append to all_clean_tables
all_values = extract_values_from_sheets(xl)
all_clean_tables['Max Likelihood Estimates'] = all_values

# Output all clean tables
print(all_clean_tables)

# Optionally, save all clean tables to a new Excel file
all_clean_tables.to_excel('regression_tables.xlsx', index=False)
