import pandas as pd
from bs4 import BeautifulSoup
from io import StringIO

# Read the HTML file
with open(r'C:\Users\saschuma\Downloads\Re_ Code feedback\Infant 070224.html', 'r', encoding='utf-8') as file:
    soup = BeautifulSoup(file, 'html.parser')

# Find all tables in the HTML
tables = soup.find_all('table')

# Create an Excel writer object
writer = pd.ExcelWriter('output.xlsx', engine='xlsxwriter')
workbook = writer.book
worksheet = workbook.add_worksheet()

# Initialize row counter
row = 0

# Write each table to the Excel sheet
for i, table in enumerate(tables):
    # Parse the table with pandas using StringIO
    df = pd.read_html(StringIO(str(table)))[0]
    
    # Reset the index
    df.reset_index(drop=True, inplace=True)

    # Write the DataFrame to the Excel sheet
    df.to_excel(writer, sheet_name='Sheet1', startrow=row, startcol=0, index=True)

    # Increment the row counter
    row += df.shape[0] + 3  # Add extra rows between tables

# Close the Excel writer object
writer.close()
