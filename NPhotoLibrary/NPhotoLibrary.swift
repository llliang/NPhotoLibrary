//
//  NPhotoLibrary.swift
//  NPhotoLibrary
//
//  Created by jiangliang on 05/02/2018.
//  Copyright © 2018 Jiang Liang. All rights reserved.
//


import UIKit
import Photos

// MARK:
public class NPhotoPrivacyAuthorizationManager: NSObject {
    static let manager = NPhotoPrivacyAuthorizationManager()
    
    @objc public enum PrivacyType: Int {
        case library
        case camera
    }
    
    public typealias AuthorizationResult = (_ type: PrivacyType ,_ state: AuthorizationStatus) -> (Void)
    
    @objc public enum AuthorizationStatus: Int {
        case notDetermined
        case restricted
        case authorized
        case denied
    }
    
    @objc public class func authorizationStatus(type: PrivacyType) -> AuthorizationStatus {
        if type == .library {
            return manager.getPhotoLibraryState()
        } else {
            return manager.getCameraState()
        }
    }
    
    var authorizationStatusMonitoring: AuthorizationResult?
    
    @objc public class func requestAuthorization(authorization: @escaping AuthorizationResult) {
        
        manager.authorizationStatusMonitoring = authorization
        
        let state = manager.getPhotoLibraryState()
        if state == .notDetermined {
            PHPhotoLibrary.requestAuthorization({ (state) in
                DispatchQueue.main.async {
                    manager.authorizationStatusMonitoring!(PrivacyType.library, manager.convertPhotoLibraryState(state: state))
                }
            })
        } else {
            manager.authorizationStatusMonitoring!(PrivacyType.library, manager.getPhotoLibraryState())
        }
    }
    
    class func requestCameraAuthorization(authorization: @escaping AuthorizationResult) {
        let state = manager.getCameraState()
        if state == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { allowed in
                DispatchQueue.main.async {
                    if allowed {
                        authorization(PrivacyType.camera, AuthorizationStatus.authorized)
                        
                        manager.authorizationStatusMonitoring!(PrivacyType.camera, AuthorizationStatus.authorized)
                    } else {
                        authorization(PrivacyType.camera, AuthorizationStatus.denied)
                        
                        manager.authorizationStatusMonitoring!(PrivacyType.camera, AuthorizationStatus.denied)
                    }
                }
            })
        } else {
            authorization(PrivacyType.camera ,state)
            
            manager.authorizationStatusMonitoring!(PrivacyType.camera ,state)
        }
    }
    
    // MARK: -------- private method
    
    /// photo library
    private func getPhotoLibraryState() -> AuthorizationStatus {
        let state = PHPhotoLibrary.authorizationStatus()
        return self.convertPhotoLibraryState(state: state)
    }
    
    private func convertPhotoLibraryState(state: PHAuthorizationStatus) -> AuthorizationStatus {
        if state == .notDetermined {
            return AuthorizationStatus.notDetermined
        } else if state == .restricted {
            return AuthorizationStatus.restricted
        } else if state == .authorized {
            return AuthorizationStatus.authorized
        } else {
            return AuthorizationStatus.denied
        }
    }
    
    // camera
    private func getCameraState() -> AuthorizationStatus {
        let state = AVCaptureDevice.authorizationStatus(for: .video)
        return self.convertCameraState(state: state)
    }
    
    private func convertCameraState(state: AVAuthorizationStatus) -> AuthorizationStatus {
        if state == .notDetermined {
            return AuthorizationStatus.notDetermined
        } else if state == .restricted {
            return AuthorizationStatus.restricted
        } else if state == .authorized {
            return AuthorizationStatus.authorized
        } else {
            return AuthorizationStatus.denied
        }
    }
}

// MARK: NImagePickerViewController

let numberOfRow = 4
let iternalWidth: CGFloat = 3.0
let collectionCellIdentifier = "collectionCellIdentifier"
let collectionCameraCellIdentifier = "collectionCameraCellIdentifier"
let collectionViewItemWidth = (UIScreen.main.bounds.size.width - CGFloat((numberOfRow + 1)) * iternalWidth)/CGFloat(numberOfRow)

typealias SelectedImagesCallback = (Array<UIImage>) -> Void

public class NPhotoPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPhotoLibraryChangeObserver {
    
    /// permissible maximum number of selected
    public var maxCount: Int = 0
    
    /// left button title; default reset navigationItem.title
    public var leftNavigationItemTitle = "cancel"
    
    /// right button title; default reset navigationItem.title
    public var rightNavigationItemTitle = "done"
    
    /// title; default reset navigationItem.title
    public var titleText: String?
    
    /// selected the callback of the images
    public func selectedImages(callback : @escaping (Array<UIImage>) -> (Void)) {
        self.imagesCallBack = callback
    }
    
    /// isChoosen : selected state , index : the index of the selected asset
    typealias AssetChoosenState = (isChoosen: Bool, index: Int)
    
    // this viewController is pushed or presented
    var isPushed: Bool = false
    
    var imagesCallBack: SelectedImagesCallback? = nil
    
    var collectionLayout = CustomCollectionViewLayout()
    
    var navigationView: CustomNavigationBar?
    var collectionView: UICollectionView?
    
    // current selected assets , it will be changed when refreshed so compare local localIdentifier
    var selectedAssets: NSMutableArray? = {
        return NSMutableArray()
    }()
    
    // current selected cells index
    typealias SelectedCellsIndex = (cell: CustomCollectionViewCell, index: Int)
    
    var selectedCells: NSMutableArray? = {
        return NSMutableArray()
    }()
    
    lazy var fetchOptions: PHFetchOptions = {
        let options = PHFetchOptions.init()
        let sortDescriptor = NSSortDescriptor(key: "creationDate", ascending: false)
        options.sortDescriptors = [sortDescriptor]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        options.includeAssetSourceTypes = PHAssetSourceType.typeUserLibrary
        
        return options
    }()
    
    var fetchResult: PHFetchResult<PHAsset>?
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.white
        self.layoutSubviews()
        
        self.requestPhotos()
        PHPhotoLibrary.shared().register(self)
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isPushed = self.isMovingToParentViewController
        navigationView?.leftButton?.setTitle(leftNavigationItemTitle, for: .normal)
        navigationView?.rightButton?.setTitle(rightNavigationItemTitle, for: .normal)
        navigationView?.titleLabel?.text = titleText
        if isPushed {
            self.navigationController?.navigationBar.isHidden = true
        }
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.navigationBar.isHidden = false
    }
    
    @available(iOS 11.0, *)
    override public func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationView?.frame = CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: self.view.safeAreaInsets.top + 44)
        navigationView?.contentView?.frame = CGRect(x: 0, y: self.view.safeAreaInsets.top, width: self.view.frame.size.width, height: 44)
        collectionView?.frame = CGRect(x: 0, y: navigationView!.frame.size.height, width: self.view.frame.size.width, height: self.view.frame.size.height - navigationView!.frame.size.height)
    }
    
    func layoutSubviews() {
        navigationView = CustomNavigationBar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 64))
        self.view.addSubview(navigationView!)
        navigationView?.contentView?.frame = CGRect(x: 0, y: 20, width: self.view.frame.size.width, height: 44)
        
        navigationView?.leftButton?.addTarget(self, action: #selector(backAction), for: .touchUpInside)
        navigationView?.rightButton?.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        
        collectionView = UICollectionView(frame: CGRect(x: 0, y: navigationView!.frame.size.height, width: self.view.frame.size.width, height: self.view.frame.size.height - navigationView!.frame.size.height), collectionViewLayout: collectionLayout)
        collectionView?.backgroundColor = UIColor.clear
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.alwaysBounceVertical = true
        collectionView?.register(CustomCollectionViewCameraCell.self, forCellWithReuseIdentifier: collectionCameraCellIdentifier)
        collectionView?.register(CustomCollectionViewCell.self, forCellWithReuseIdentifier: collectionCellIdentifier)
        
        self.view.addSubview(collectionView!)
    }
    
    func requestPhotos() {
        fetchResult = PHAsset.fetchAssets(with: fetchOptions)
    }
    
    // MARK: UICollectionViewDelegate UICollectionViewDataSource
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if fetchResult == nil {
            return 1
        }
        return fetchResult!.count + 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.row == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: collectionCameraCellIdentifier, for: indexPath)
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: collectionCellIdentifier, for: indexPath) as! CustomCollectionViewCell
            
            let asset = fetchResult?.object(at: indexPath.row - 1)
            let state = self.isChoosen(asset: asset!)
            cell.isChoosen = state.isChoosen
            if state.isChoosen {
                cell.index = state.index + 1
                selectedCells?.add((cell, state.index))
            }
            cell.asset = fetchResult?[indexPath.row - 1]
            return cell
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            NPhotoPrivacyAuthorizationManager.requestCameraAuthorization(authorization: { (type, state) -> (Void) in
                if state == NPhotoPrivacyAuthorizationManager.AuthorizationStatus.authorized {
                    let cameraViewController = UIImagePickerController()
                    cameraViewController.delegate = self
                    cameraViewController.sourceType = UIImagePickerControllerSourceType.camera
                    self.present(cameraViewController, animated: true, completion: nil)
                }
            })
            return
        }
        let cell = collectionView.cellForItem(at: indexPath) as! CustomCollectionViewCell
        let asset = fetchResult?.object(at: indexPath.row - 1)
        
        let choosen = self.isChoosen(asset: asset!)
        
        if choosen.isChoosen {
            self.deleteChoosenAsset(asset: asset!)
            cell.isChoosen = false
            self.removeAt(index: choosen.index)
            self.refreshSelectedCells()
        } else {
            if maxCount > 0 && selectedAssets!.count >= maxCount {
                self.showAlertController()
                return
            }
            selectedAssets?.add(asset!)
            selectedCells?.add((cell: cell,index: selectedCells!.count))
            cell.isChoosen = true
            cell.index = selectedAssets!.index(of: asset!) + 1
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionViewItemWidth, height: collectionViewItemWidth)
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(iternalWidth, iternalWidth, iternalWidth, iternalWidth)
    }
    
    // MARK: UIImagePickerControllerDelegate
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion: nil)
        let image = info[UIImagePickerControllerOriginalImage] as! UIImage
        
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(image:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: AnyObject) {
        self.requestPhotos()
        
        selectedAssets?.add(fetchResult?.firstObject as Any)
    }
    
    // MARK: PHPhotoLibraryChangeObserver
    
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            let detail = changeInstance.changeDetails(for: self.fetchResult!)
            if let _ = detail {
                if detail!.hasIncrementalChanges {
                    let removedObjects: [PHAsset] = detail!.removedObjects
                    if !removedObjects.isEmpty {
                        for asset in removedObjects {
                            self.deleteChoosenAsset(asset: asset)
                        }
                    }
                    
                    let changedObjects: [PHAsset] = detail!.changedObjects
                    if !changedObjects.isEmpty {
                        for asset in changedObjects {
                            self.exchangeObject(asset: asset)
                        }
                    }
                    self.reloadCollectionView()
                }
            }
        }
    }
    
    func removeAt(index: Int) {
        
        let tmpArray = NSMutableArray(array: selectedCells!)
        var needDeleteIndex = -1
        for i in 0 ..< selectedCells!.count {
            var cell = selectedCells![i] as! SelectedCellsIndex
            if cell.index == index {
                needDeleteIndex = i
                continue
            } else if cell.index > index {
                cell.index = cell.index - 1
                tmpArray.replaceObject(at: i, with: cell)
            }
        }
        if needDeleteIndex >= 0 {
            tmpArray.removeObject(at: needDeleteIndex)
        }
        selectedCells = NSMutableArray(array: tmpArray)
    }
    
    func refreshSelectedCells() {
        for obj in selectedCells! {
            let cell = obj as! SelectedCellsIndex
            cell.cell.index = cell.index + 1
        }
    }
    
    func reloadCollectionView() {
        self.requestPhotos()
        selectedCells?.removeAllObjects()
        collectionView?.reloadData()
    }
    
    func isChoosen(asset: PHAsset) -> AssetChoosenState {
        for obj in selectedAssets! {
            let selectedObj = obj as! PHAsset
            if asset.localIdentifier == selectedObj.localIdentifier {
                return (true, selectedAssets!.index(of: obj))
            }
        }
        return (false, 0)
    }
    
    func showAlertController() {
        let alertController = UIAlertController(title: nil, message: "最多只能选择\(maxCount)张照片", preferredStyle: UIAlertControllerStyle.alert)
        let action = UIAlertAction(title: "我知道了", style: UIAlertActionStyle.cancel) { (action) in
            
        }
        alertController.addAction(action)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func deleteChoosenAsset(asset: PHAsset) {
        let array = NSArray(array: selectedAssets!)
        for obj in array {
            let selectedObj = obj as! PHAsset
            if selectedObj.localIdentifier == asset.localIdentifier {
                selectedAssets?.removeObject(at: array.index(of: obj))
                break
            }
        }
    }
    
    func exchangeObject(asset: PHAsset) {
        let array = NSArray(array: selectedAssets!)
        for obj in array {
            let selectedObj = obj as! PHAsset
            if selectedObj.localIdentifier == asset.localIdentifier {
                selectedAssets?.replaceObject(at: array.index(of: obj), with: asset)
                break
            }
        }
    }
    
    // MARK: actions
    @objc private func backAction() {
        if isPushed {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func doneAction() {
        if selectedAssets!.count > 0 {
            self.imagesCallBack!(self.handleAssets())
        }
        self.backAction()
    }
    
    func handleAssets() -> Array<UIImage> {
        var images = [UIImage]()
        for obj in selectedAssets! {
            let asset = obj as! PHAsset
            
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = true
            
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: PHImageContentMode.aspectFill, options: options, resultHandler: { (image, info) in
                if let _ = image {
                    images.append(image!)
                }
            })
        }
        return images
    }
}

class CustomCollectionViewLayout: UICollectionViewFlowLayout {
    override init() {
        super.init()
        self.minimumLineSpacing = iternalWidth
        self.minimumInteritemSpacing = iternalWidth
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class CustomNavigationBar: UIView {
    
    var contentView: UIView?
    var leftButton: UIButton?
    var rightButton: UIButton?
    var titleLabel: UILabel?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView = UIView(frame:CGRect(x: 0, y: 0, width: self.frame.size.width, height: 44))
        self.addSubview(contentView!)
        
        leftButton = UIButton(frame: CGRect(x: 20, y: 0, width: 50, height: contentView!.frame.size.height))
        leftButton?.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        leftButton?.setTitleColor(UIColor.darkText, for: .normal)
        leftButton?.contentHorizontalAlignment = UIControlContentHorizontalAlignment.left
        contentView?.addSubview(leftButton!)
        
        titleLabel = UILabel(frame: CGRect(x: leftButton!.frame.origin.x + leftButton!.frame.size.width, y: 0, width: self.frame.size.width - 20*2 - leftButton!.frame.size.width*2, height: contentView!.frame.size.height))
        titleLabel?.font = UIFont.systemFont(ofSize: 16);
        titleLabel?.textAlignment = .center
        titleLabel?.textColor = UIColor.darkText
        contentView?.addSubview(titleLabel!)
        
        rightButton = UIButton(frame: CGRect(x: titleLabel!.frame.origin.x + titleLabel!.frame.size.width, y: 0, width: leftButton!.frame.size.width, height: contentView!.frame.size.height))
        rightButton?.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        rightButton?.setTitleColor(UIColor.darkText, for: .normal)
        rightButton?.contentHorizontalAlignment = UIControlContentHorizontalAlignment.right
        contentView?.addSubview(rightButton!)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class CameraImageView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let path = CGMutablePath()
        
        let cameraView = UIView(frame: CGRect(x: (frame.size.width - 50)/2.0, y: (frame.size.height - 40)/2.0, width: 50, height: 40))
        cameraView.backgroundColor = UIColor(white: 0, alpha: 0.3)
        self.addSubview(cameraView)
        
        path.move(to: CGPoint(x: 0, y: 14))
        // top left corner
        path.addArc(tangent1End: CGPoint(x: 0, y: 8), tangent2End: CGPoint(x: 6, y: 8), radius: 3)
        path.addLine(to: CGPoint(x: 13, y: 8))
        path.addLine(to: CGPoint(x: 19, y: 0))
        path.addLine(to: CGPoint(x: 31, y: 0))
        path.addLine(to: CGPoint(x: 37, y: 8))
        path.addLine(to: CGPoint(x: 44, y: 8))
        
        // top right corner
        path.addArc(tangent1End: CGPoint(x: 50, y: 8), tangent2End: CGPoint(x: 50, y: 14), radius: 3)
        path.addLine(to: CGPoint(x: 50, y: 34))
        
        //lower right corner
        path.addArc(tangent1End: CGPoint(x: 50, y: 40), tangent2End: CGPoint(x: 44, y: 40), radius: 3)
        path.addLine(to: CGPoint(x: 6, y: 40))
        
        // lower left corner
        path.addArc(tangent1End: CGPoint(x: 0, y: 40), tangent2End: CGPoint(x: 0, y: 34), radius: 3)
        path.addLine(to: CGPoint(x: 0, y: 13))
        path.closeSubpath()
        
        let ringPath = CGMutablePath()
        ringPath.addRoundedRect(in: CGRect(x: 17, y: 15, width: 16, height: 16), cornerWidth: 8, cornerHeight: 8)
        ringPath.closeSubpath()
        let ringLayer = CAShapeLayer()
        ringLayer.lineWidth = 4
        ringLayer.strokeColor = UIColor.white.cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.path = ringPath
        
        let cameralayer = CAShapeLayer()
        cameralayer.path = path
        
        cameraView.layer.mask = cameralayer
        cameraView.layer.addSublayer(ringLayer)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class CustomCollectionViewCameraCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let cameraView = CameraImageView(frame: self.bounds)
        cameraView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        self.contentView.addSubview(cameraView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class CustomCollectionViewCell: UICollectionViewCell {
    
    var imageView: UIImageView?
    var coverView: UIView?
    // top left corner
    var topLeftView: UIView?
    var indexLabel: UILabel?
    
    var imageRequestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.resizeMode = PHImageRequestOptionsResizeMode.exact
        return options
    }()
    
    var isChoosen: Bool {
        didSet {
            coverView?.isHidden = !isChoosen
        }
    }
    
    var index: Int? {
        didSet {
            let indexString: NSString = NSString(format: "%d", index!)
            let width = indexString.boundingRect(with: CGSize(width: CGFloat(MAXFLOAT), height: indexLabel!.frame.size.height), options: NSStringDrawingOptions.usesFontLeading, attributes: nil, context: nil).width
            topLeftView?.frame = CGRect(x: coverView!.frame.size.width - width - 5 - 5, y: topLeftView!.frame.origin.y, width: width + 5 + 5, height: topLeftView!.frame.size.height)
            
            indexLabel?.frame = CGRect(x: topLeftView!.frame.size.width - width - 5, y: indexLabel!.frame.origin.y, width: width, height: indexLabel!.frame.size.height)
            indexLabel?.text = indexString as String
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: topLeftView!.bounds, byRoundingCorners: UIRectCorner.bottomLeft, cornerRadii: CGSize(width: 10, height: 16)).cgPath
            topLeftView?.layer.mask = maskLayer
        }
    }
    
    var asset: PHAsset? {
        didSet {
            let width = UIScreen.main.scale * collectionViewItemWidth
            PHImageManager.default().requestImage(for: asset!, targetSize: CGSize(width: width, height: width), contentMode: PHImageContentMode.aspectFill, options: imageRequestOptions) { (image, info) in
                self.imageView?.image = image
            }
        }
    }
    
    override init(frame: CGRect) {
        self.isChoosen = false
        super.init(frame: frame)
        
        imageView = UIImageView(frame: self.bounds)
        imageView?.isUserInteractionEnabled = true
        self.addSubview(imageView!)
        
        let color = UIColor(red: 32/255.0, green: 220/255.0, blue: 143/255.0, alpha: 1)
        
        coverView = UIView(frame: imageView!.bounds)
        coverView?.backgroundColor = UIColor(white: 1, alpha: 0.3)
        coverView?.isHidden = true
        coverView?.layer.borderColor = color.cgColor
        coverView?.layer.borderWidth = 3
        self.addSubview(coverView!)
        
        topLeftView = UIView(frame: CGRect(x: coverView!.frame.size.width - 20, y: 0, width: 20, height: 16))
        topLeftView?.backgroundColor = color
        coverView?.addSubview(topLeftView!)
        
        indexLabel = UILabel(frame: CGRect(x: topLeftView!.frame.size.width - 5, y: 0, width: 0, height: topLeftView!.frame.size.height))
        indexLabel?.font = UIFont.systemFont(ofSize: 12)
        indexLabel?.textColor = UIColor.white
        indexLabel?.textAlignment = NSTextAlignment.right
        topLeftView?.addSubview(indexLabel!)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
