//
//  WeekViewController.swift
//  Meal Planner
//
//  Created by Clayton, David on 2/23/18.
//  Copyright © 2018 Clayton, David. All rights reserved.
//

import UIKit
import Foundation
import CoreData
import GameplayKit
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import FirebaseUI

class WeekViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    var meal = Meal()
    var mealArray = [Meal]()
    var mealsToShuffleArray = [Meal]()
    var mealSortedOrderArray = [Meal]()
    var mealToReplace = Meal()
    var mealReplacing = Meal()
    var handle : Any?
    var ref : DatabaseReference!
    var user : User?
    var uid : String?
    var email : String?
    
    // Firebase Storage
    let storage = Storage.storage()
    var imagesFolderReference: StorageReference {
            return Storage.storage().reference().child("images")
        }
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkCurrentUser()
        
        mealArray = []
        retrieveMealsFromFirebase()
        
        tableView.register(UINib(nibName: "mealXib", bundle: nil), forCellReuseIdentifier: "customMealCell")
        self.tableView.backgroundColor = UIColor.white
        self.tableView.delegate = self
        self.tableView.dataSource = self

    }
    
    override func viewWillAppear(_ animated: Bool) {
        //MARK: Google analytics stuff
        guard let tracker = GAI.sharedInstance().defaultTracker else { return }
        tracker.set(kGAIScreenName, value: "Week view controller")
        
        guard let builder = GAIDictionaryBuilder.createScreenView() else { return }
        tracker.send(builder.build() as [NSObject : AnyObject])
        //End google analytics stuff.
        
        //Firebase auth
        handle = Auth.auth().addStateDidChangeListener { (auth, user) in
            print("Added auth state change listener.")
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.tableView.backgroundColor = UIColor.white
        tableView.register(UINib(nibName: "mealXib", bundle: nil), forCellReuseIdentifier: "customMealCell")
        
        sortMeals()
        tableView.reloadData()
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        saveMealsToFirebase()
        
        //Firebase auth. Added "as! AuthStateDidChangeListenerHandle" because var handle is of type 'Any?'.
        Auth.auth().removeStateDidChangeListener(handle! as! AuthStateDidChangeListenerHandle)
        print("Removed auth state change listener.")
    }
    
    func checkCurrentUser() {
        if Auth.auth().currentUser != nil {
            self.user = Auth.auth().currentUser
            if let thisUser = user {
                uid = thisUser.uid
                email = thisUser.email
                print("\(uid!) is signed in and their email is \(email!).")
            }
        } else {
            print("Nobody is signed in.")
        }
    }
    
    //MARK: Tableview datasource methods
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let meal = mealArray[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "customMealCell", for: indexPath) as! CustomMealCell
        
        // Set meal name
        if meal.mealName == nil {
            meal.mealName = "Meal name"
            meal.mealLocked = false
        } else {
            cell.mealLabel?.text = meal.mealName!
        }
        
        // Set meal image
        cell.mealImage.contentMode = .scaleAspectFill
        if meal.mealImagePath == nil {
            cell.mealImage.image = UIImage(named: "mealPlaceholder")
        } else if meal.mealImagePath == "" {
            cell.mealImage.image = UIImage(named: "mealPlaceholder")
        } else {
            // FirebaseUI method
            let imgReference = storage.reference().child("images/\(meal.mealImagePath!).jpg")
            print("Image reference is \(imgReference)")
            let thisImageView = cell.mealImage
            thisImageView?.sd_setImage(with: imgReference, placeholderImage: #imageLiteral(resourceName: "mealPlaceholder"))
        }
        
        // Set mealDay label to day of the week depending on what row of the table it's in.
        if indexPath.row == 0 {
            cell.mealDay?.text = "Sunday" }
        else if indexPath.row == 1 {
            cell.mealDay?.text = "Monday"
        } else if indexPath.row == 2 {
            cell.mealDay?.text = "Tuesday"
        } else if indexPath.row == 3 {
            cell.mealDay?.text = "Wednesday"
        } else if indexPath.row == 4 {
            cell.mealDay?.text = "Thursday"
        } else if indexPath.row == 5 {
            cell.mealDay?.text = "Friday"
        } else if indexPath.row == 6 {
            cell.mealDay?.text = "Saturday"
        } else if indexPath.row > 6 {
            cell.isHidden = true
        }
        
        // Color cell if it's locked.
        if meal.mealLocked == true {
            cell.backgroundColor = UIColor(rgb: 0xFCEADE).withAlphaComponent(1.0)
            cell.mealLockIconBtn.setImage(#imageLiteral(resourceName: "twotone_lock_black_24pt"), for: .normal)
        } else {
            cell.backgroundColor = UIColor.clear
            cell.mealLockIconBtn.setImage(#imageLiteral(resourceName: "twotone_lock_open_black_24pt"), for: .normal)
        }
        
        // Accessing the lock button inside CustomMealCell
        cell.onLockTapped = {
            self.lockMeal(mealToCheck: meal, cellToColor: cell)
        }
        
        // Accessing the swap button inside CustomMealCell
        cell.onSwapTapped = {
            self.mealSwapTapped(cell)
            self.performSegue(withIdentifier: "segueToReplaceMeal", sender: UIButton.self)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if mealArray.count < 7 {
            return mealArray.count
        } else {
            return 7
        }
    }
    
    //MARK: Override to support editing the table view. Swipe to delete.
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            
            let mealToDelete = self.mealArray[indexPath.row]
            
            // alert
            let alert = UIAlertController(title: "Delete \(mealToDelete.mealName!)?", message: "", preferredStyle: .alert)
            let action = UIAlertAction(title: "Delete", style: .default) { (action) in
                
                // stuff that happens when user taps delete
                // delete meal from array
                self.mealArray.remove(at: indexPath.row)
                
                // delete meal from firebase
                self.ref.child(mealToDelete.mealFirebaseID!).removeValue()
                
                // delete image associated with meal
                if mealToDelete.mealImagePath != nil {
                    print("Image is \(mealToDelete.mealImagePath!)")
                    self.imagesFolderReference.child(mealToDelete.mealImagePath! + ".jpg").delete { (error) in
                        if error != nil {
                            print(error!)
                        } else {
                            print("Deleted image.")
                        }
                    }
                }
                
                print("Deleted \(mealToDelete.mealName!).")
                //TODO: Save meals to Firebase database
                self.saveMealsToFirebase()
                
                self.tableView.reloadData()
            }
            
            let cancel = UIAlertAction(title: "Cancel", style: .cancel) { (action) in
                // do nothing
                print("Cancelled")
            }
            alert.addAction(cancel)
            alert.addAction(action)
            present(alert, animated: true, completion: nil)
    }
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        print("can move rows")
        
        return true
    }
    func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
        let itemToMove = mealArray[fromIndexPath.row]
        mealArray.remove(at: fromIndexPath.row)
        mealArray.insert(itemToMove, at: toIndexPath.row)

        //TODO: Save meals to Firebase database
        saveMealsToFirebase()
    }
    
    //MARK: Reordering controls and tableView methods
    @IBAction func editPressed(_ sender: UIBarButtonItem) {
        // Editing meals to be able to reorder them
        //        self.isEditing = !self.isEditing
        if tableView.isEditing == false {
            setEditing(true, animated: true)
        } else {
            setEditing(false, animated: true)
        }
    }
    
    //MARK: Lock meal function
    func lockMeal(mealToCheck : Meal, cellToColor : UITableViewCell) {
        
        if mealToCheck.mealLocked == true {
            mealToCheck.mealLocked = false
            print("\(mealToCheck.mealName!) unlocked")
            cellToColor.backgroundColor = UIColor.clear
        } else if mealToCheck.mealLocked == false {
            mealToCheck.mealLocked = true
            print("\(mealToCheck.mealName!) locked")
            cellToColor.backgroundColor = UIColor.lightGray
        }
        
        //TODO: Save meals to Firebase database
        saveMealsToFirebase()
    }
    
    //MARK: Randomize meals function
    // New way I'm going to do this:
    // 1. Go through each item in the list, and if it's unlocked put it into mealsToShuffleArray
    // 2. If it's locked, skip to the next meal in the list.
    // 3. When I reach the end/top, shuffle the meals in mealsToShuffle using shuffle function from GameplayKit.
    // 4. Go back through each item in the list, and if it's unlocked, swap in the first item from mealsToShuffleArray.
    // 5. If it's locked, skip to the next meal in the list.
    // 6. Do this swapping until eaching the end/top of the list.
    func randomize() {
        do {
            var lastMealInt : Int = mealArray.count - 1
            print("LastMealInt is \(lastMealInt).")
            // step 1
            while(lastMealInt > -1)
            {
                let mealToCheck : Meal = mealArray[lastMealInt]
                if mealToCheck.mealLocked == false {
                    mealsToShuffleArray.append(mealToCheck)
                    print("Put \(mealToCheck.mealName!) into mealsToShuffleArray.")
                }
                    // step 2
                else if mealToCheck.mealLocked == true {
                    // do nothing
                }
                lastMealInt -= 1
            }
            var lastShuffledMealInt : Int = mealsToShuffleArray.count - 1
            print("Moved \(lastShuffledMealInt) unlocked meals to mealsToShuffleArray.")
            
            // step 3: shuffle the meals
            mealsToShuffleArray = GKRandomSource.sharedRandom().arrayByShufflingObjects(in: mealsToShuffleArray) as! [Meal]
            print("Shuffled unlocked meals in mealsToShuffleArray")
            
            // reset lastMealInt to the bottom item in the list
            lastMealInt = mealArray.count - 1
            print("Reset lastMealInt. Now it's \(lastMealInt).")
            
            // step 4 - Swap everything back in
            while(lastMealInt > -1 && lastShuffledMealInt > -1)
            {
                let mealToCheck : Meal = mealArray[lastMealInt]
                let mealToSwapIn : Meal = mealsToShuffleArray[lastShuffledMealInt]
                if mealToCheck.mealLocked == false {
                    mealArray.remove(at: lastMealInt)
                    mealArray.insert(mealToSwapIn, at: lastMealInt)
                    mealsToShuffleArray.remove(at: lastShuffledMealInt)
                    
                    // Assign current position in list to mealSortedOrder
                    mealToSwapIn.mealSortedOrder = Int32(lastMealInt)
                    
                    lastShuffledMealInt -= 1
                }
                    // step 5
                else if mealToCheck.mealLocked == true {
                    // do nothing
                }
                lastMealInt -= 1
            }
        }
    }
    
    //MARK: Function to sort tableview according to mealSortedIndex
    //Pseudocode:
    //1. Go through list from bottom to top, and put each meal into mealSortedOrderArray at the sortedOrder of that meal.
    //2. When you get to the top of the list, copy over the meals from mealSortedOrderArray to mealArray.
    //3. Destroy mealSortedOrderArray (empty it out).
    func sortMeals() {
        do {
            var lastMealInt : Int = mealArray.count - 1
            mealSortedOrderArray = mealArray
            while(lastMealInt > -1)
            {
                let mealToCheck : Meal = mealArray[lastMealInt]
                do {
                    mealSortedOrderArray.remove(at: Int(mealToCheck.mealSortedOrder))
                    mealSortedOrderArray.insert(mealToCheck, at: Int(mealToCheck.mealSortedOrder))
                }
                lastMealInt -= 1
            }
            mealArray = mealSortedOrderArray
            mealSortedOrderArray = [Meal]()
        }
        print("Sorted meals.")
//        self.tableView.reloadData()
    }
    
    @IBAction func unwindToWeekMeals(segue: UIStoryboardSegue) {
        // nothing here but I think I need this.
    }
    
    //MARK: Pass in data on segue
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "segueToMealDetail" {
            if let destinationVC = segue.destination as? MealDetailViewController {
                print("Prepared for segue")
                destinationVC.cameFromWeekMeals = true
                destinationVC.cameFromAllMeals = false
                let indexPath = tableView.indexPathForSelectedRow
                destinationVC.mealPassedIn = mealArray[(indexPath?.row)!]
                print("Passed in meal")
            }
        } else if segue.identifier == "segueToReplaceMeal" {
            if let destinationVC = segue.destination as? ReplaceMealController {
                saveMealsToFirebase()
                print("Prepared for segue to replace meal")
                destinationVC.mealPassedIn = mealToReplace
                print("Passed in meal to replace")
            }
        }
    }
    
    //MARK: Tableview delegate methods - select row, segue to meal detail
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: "segueToMealDetail", sender: self)
        print("Performed segue to meal detail")
    }
    
    
    //MARK: Button to randomize the list
    @IBAction func shuffleButtonPressed(_ sender: UIBarButtonItem) {
        // Randomize the order
        randomize()
        
        // Sort them according to true order in FB
        sortMeals()
        
        self.tableView.reloadData()
        
        // Save meals to Firebase database
        saveMealsToFirebase()
    }
    
    
    @IBAction func lockButton(_ sender: CustomMealCell) {
        
        print("Setting lock state")
        
        // find parent of button, then cell, then index of row.
        let parentCell = sender.superview?.superview as! UITableViewCell
        print("set parentCell")
        
        // Fixed error - added second superview so it's not just UITableViewWrapper being cast as UITableView.
        let parentTable = parentCell.superview?.superview as! UITableView
        print("set parentTable")
        
        let indexPath = parentTable.indexPath(for: parentCell)
        print("set indexPath")
        
        let mealToLock = self.mealArray[indexPath!.row]
        print("set mealToLock")
        
        // Use index of row to set mealLocked of meal to true/false
        lockMeal(mealToCheck: mealToLock, cellToColor: parentCell)
    }
    
    @IBAction func mealSwapTapped(_ sender: CustomMealCell ) {
        print("Tapped swap button")
        
        // find parent of button, then cell, then index of row.
        //        let parentCell = sender.superview?.superview as! UITableViewCell
        //        print("set parentCell")
        let parentCell = sender as UITableViewCell
        print("set parentCell")
        
        // Fixed error - added second superview so it's not just UITableViewWrapper being cast as UITableView.
        let parentTable = parentCell.superview as! UITableView
        print("set parentTable")
        
        let indexPath = parentTable.indexPath(for: parentCell)
        print("set indexPath")
        
        mealToReplace = mealArray[indexPath!.row]
        print("Set mealToReplace to \(mealToReplace.mealName!)")
        
    }
    
    // Load meals from Firebase database
    // This was causing the app to crash, but I added a var 'ref : DatabaseReference!' to the beginning of the controller.
    func retrieveMealsFromFirebase() {
        if uid != nil {
            ref = Database.database().reference().child("Meals").child(user!.uid)
            ref.observe(.childAdded) { (snapshot : DataSnapshot) in
                let snapshotValue = snapshot.value as! Dictionary<String, Any>
                let mealFromFB = Meal(context: self.context)
                
                mealFromFB.mealImagePath = snapshotValue["MealImagePath"] as? String
                mealFromFB.mealIsReplacing = snapshotValue["MealIsReplacing"] as! Bool
                mealFromFB.mealLocked = snapshotValue["MealLocked"] as! Bool
                mealFromFB.mealName = snapshotValue["MealName"] as? String
                mealFromFB.mealOwner = snapshotValue["MealOwner"] as? String
                mealFromFB.mealRecipeLink = snapshotValue["MealRecipeLink"] as? String
                mealFromFB.mealReplaceMe = snapshotValue["MealReplaceMe"] as! Bool
                mealFromFB.mealSortedOrder = snapshotValue["MealSortedOrder"] as! Int32
                mealFromFB.mealFirebaseID = snapshotValue["MealFirebaseID"] as? String
                
                print("\(mealFromFB.mealName ?? "Meal name") sortedOrder is \(mealFromFB.mealSortedOrder).")
                self.mealArray.append(mealFromFB)
//                self.mealArray.insert(mealFromFB, at: Int(mealFromFB.mealSortedOrder))
                
                self.tableView.reloadData()
            }
        }
        else {
            print("User ID was nil.")
        }
    }
    
    //MARK: Save to Firebase function
    func saveMealsToFirebase() {
        if uid != nil {
            self.ref = Database.database().reference().child("Meals").child(self.user!.uid)
            
            self.title = "Saving..." // Only changes title in bottom tab bar.
//            self.navigationItem.title = "Saving" // doesn't work
//            self.tabBarController?.navigationItem.title = "My Title" // doesn't work
//            self.navigationController?.title = "test" // doesn't work
            // Week view controller > view > navigation bar > navigation item > title
            
            do {
                var lastMealInt : Int = mealArray.count - 1
                lastMealInt = mealArray.count - 1
//                mealSortedOrderArray = mealArray
                while(lastMealInt > -1)
                {
                    let mealToCheck : Meal = mealArray[lastMealInt]
                    do {
                        // do stuff to that meal
                        // Create dictionary for that meal
                        let mealDictionary = ["MealOwner": Auth.auth().currentUser?.email ?? "",
                                              "MealName": mealToCheck.mealName!,
                                              "MealLocked": mealToCheck.mealLocked,
                                              "MealSortedOrder": mealToCheck.mealSortedOrder,
                                              "MealImagePath": mealToCheck.mealImagePath ?? "",
                                              "MealIsReplacing": mealToCheck.mealIsReplacing,
                                              "MealRecipeLink": mealToCheck.mealRecipeLink ?? "http://www.allrecipes.com",
                                              "MealReplaceMe": mealToCheck.mealReplaceMe,
                                              "MealFirebaseID": mealToCheck.mealFirebaseID!
                            ] as [String : Any]
                        
                        let mealFirebaseIDDataRef = mealToCheck.mealFirebaseID
                        
                        self.ref.child(mealFirebaseIDDataRef!).setValue(mealDictionary) {
                            (error, reference) in
                            if error != nil {
                                print(error!)
                            } else {
                                print("Meal saved successfully to Firebase")
                            }
                        }
                    }
                    lastMealInt -= 1
                }
            }
            self.title = "Week"
    }
    }

}



extension UIColor {
    convenience init(red: Int, green: Int, blue: Int) {
        assert(red >= 0 && red <= 255, "Invalid red component")
        assert(green >= 0 && green <= 255, "Invalid green component")
        assert(blue >= 0 && blue <= 255, "Invalid blue component")
        self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1.0)
    }
    
    convenience init(rgb: Int) {
        self.init(
            red: (rgb >> 16) & 0xFF,
            green: (rgb >> 8) & 0xFF,
            blue: rgb & 0xFF
        )
    }
}



