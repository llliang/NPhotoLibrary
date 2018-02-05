# NPhotoLibrary

## example
```
NPhotoPrivacyAuthorizationManager.requestAuthorization { (type, state) -> (Void) in
            if type == NPhotoPrivacyAuthorizationManager.PrivacyType.library && state == NPhotoPrivacyAuthorizationManager.AuthorizationStatus.authorized {
                let imageController = NPhotoPickerViewController()
                imageController.maxCount = 9 // The maximum number of selection
                imageController.selectedImages(callback: { (images) -> (Void) in
                    // results images
                })
                self.present(imageController, animated: true, completion: nil)
                //                self.navigationController?.pushViewController(imageController, animated: true)
            } else {
                print("PrivacyType--%d, AuthorizationStatus--%d", type, state)
            }
        }
```
