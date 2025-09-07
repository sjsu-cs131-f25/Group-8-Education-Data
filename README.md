## Downloading the Dataset

This project uses the **Student Performance and Learning Style** dataset from Kaggle.

### Steps to Download

1. Go to the dataset page on Kaggle:  
   [https://www.kaggle.com/datasets/adilshamim8/student-performance-and-learning-style](https://www.kaggle.com/datasets/adilshamim8/student-performance-and-learning-style)

2. If you don’t have a Kaggle account, **sign up** and log in.

3. Click the **"Download"** button on the top-right of the page. This will download a ZIP file containing the dataset.

4. Extract the ZIP file and move the CSV files (or relevant data files) into the `data/` directory of this repository.

5. Make sure the files are in the `data/` folder so your code can access them correctly.

---

If you have the Kaggle API installed, you can also download the dataset directly:

```bash
# Install Kaggle API if not already installed
pip install kaggle

# Make sure your Kaggle API token is set up (kaggle.json)
# Then run:
kaggle datasets download -d adilshamim8/student-performance-and-learning-style -p data/ --unzip
