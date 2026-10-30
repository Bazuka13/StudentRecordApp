# AuraCampus ERP - Student Information & Management System

> Next-generation Campus ERP and Student Information System (SIS) built with Flask, AWS DynamoDB (with SQLite fallback), and a modern, responsive Glassmorphism UI.

---

## 🌟 Key Features

### 🎓 1. Student Self-Service Portal
- **Profile & Digital Smart ID Card**: View student identity, registration number, course, department, mentor, and download/print digital smart ID cards.
- **Smart Safe-Leave & Bunk Planner**: Real-time attendance buffer calculator that forecasts exactly how many lectures can be safely missed while maintaining attendance compliance ($>=75\%$), or how many consecutive classes must be attended to recover.
- **Academics & Enrolled Courses**: Course schedule, credits, instructor details, room locations, and 1-click elective registration.
- **Official Semester Transcript**: Course-wise credit breakdown, letter grades ($A+, A, B+$), grade points, and cumulative GPA (CGPA) with formatted print view.
- **Financial Ledger & Instant Fee Clearance**: Itemized semester statement (Tuition, Labs, Library, Examinations), transaction history, and instant online payment simulator with authenticated digital fee receipts.
- **Weekly Class Timetable**: Day-by-day class schedule (Monday through Friday) showing lecture timings, course codes, classrooms, and professor names.
- **Campus Bulletin & Notices**: University announcement board with priority badges (Urgent, High, Normal).

### ⚙️ 2. Faculty & Institutional Admin ERP
- **Institutional Analytics**: Real-time KPI metrics for total enrolled students, institutional average CGPA, attendance compliance ratio, and fee receivables.
- **Student Roster Management**: Searchable and filterable student directory with instant search (by name, roll no, email, department) and compliance filtering ($>=75\%$ vs $<75\%$).
- **Fast Registration & Comprehensive Modals**: Fast student registration bar plus a detailed registration modal for full academic and financial onboarding.
- **Data Export & Sync**: Export complete student records to CSV spreadsheet or JSON with 1 click.
- **Demo Data Re-Seeding**: Reset the database to pristine demo data at any time.

### ⚡ 3. Dual-Engine Storage Architecture
- **Automatic Fallback to Local SQLite (`students.db`)**: Runs completely out of the box with zero external configuration or AWS credentials required.
- **Full AWS DynamoDB Support**: Connects to the AWS DynamoDB `StudentRecords` table automatically when AWS credentials or an EC2 IAM role are detected.
- **EC2 Cloud Ready**: Includes an automated Launch Template User Data script in `webapp/deploy/user-data.sh`.

---

## 📁 Project Structure

```text
StudentRecordApp/
├── .gitignore
├── README.md
└── webapp/
    ├── app.py                # Flask application, routing, APIs & calculations
    ├── storage.py            # Dual persistence layer (DynamoDB + SQLite fallback)
    ├── test_app.py           # Self-contained test suite
    ├── requirements.txt      # Python dependencies
    ├── deploy/
    │   └── user-data.sh      # EC2 automated launch script
    └── templates/
        └── index.html        # Modern Glassmorphic ERP UI (Student + Admin views)
```

---

## 🚀 Getting Started

### Prerequisites
- Python 3.10+
- `pip`

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Bazuka13/StudentRecordApp.git
   cd StudentRecordApp
   ```

2. **Set up a virtual environment**:
   ```bash
   python -m venv venv
   # On Windows:
   .\venv\Scripts\activate
   # On Linux/macOS:
   source venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r webapp/requirements.txt
   ```

4. **Run the application**:
   ```bash
   # On Windows PowerShell:
   $env:PORT="5000"; python webapp/app.py
   # On Linux/macOS:
   PORT=5000 python webapp/app.py
   ```

5. **Open in browser**:
   Navigate to [http://127.0.0.1:5000](http://127.0.0.1:5000)

---

## 🧪 Running Tests

Execute the automated test suite:
```bash
python webapp/test_app.py
```

---

## ☁️ AWS Deployment (Optional)

To deploy on AWS EC2:
1. Create a DynamoDB table named `StudentRecords` with partition key `studentId` (String).
2. Attach an IAM role with DynamoDB read/write permissions to your EC2 instance.
3. Paste the contents of `webapp/deploy/user-data.sh` into the instance User Data field.
