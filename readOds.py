import pandas as pd

df = pd.read_excel("celes-bridge1/blocks/0EABE2FC77D370BCA2D8E0DF4CDBAB6B2AA825E06F55A26BA1C635085EC23069.ods", engine="odf")
print(df.head())
