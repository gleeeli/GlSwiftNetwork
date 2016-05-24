//
//  ViewController.swift
//  GlSwiftNetwork
//
//  Created by gleeeli on 16/5/24.
//  Copyright © 2016年 gleeeli. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self .testGlhttpManager()
    }
    //测试get请求
    func testGlhttpManager() {
        self.view.backgroundColor = UIColor.yellowColor();
        let my:GlRequest =   GlHttpManager.request(.GET, "http://webapi.map10000.com:81/api/auth/GetUserValidate?", parameters: ["account":"vkwgs","password":"E10ADC3949BA59ABBE56E057F20F883E","loginType":"1"])
        print("my=\(my)")
        my.responseJSON { response in
            print("收到数据responseJSON：----------");
            print(response.request)
            print(response.response)
            print(response.data)
            print(response.result)
            if let JSON = response.result.value {
                print("JSON:\(JSON)")
            }
        }
    }
    
    //测试post请求
    func funTestPost() {
        let mydict = ["Account": "vkwgs","OldPassword":"E10ADC3949BA59ABBE56E057F20F883E","NewPassword":"123456","ConfirmPassword":"123"]
        let my:GlRequest = GlHttpManager.request(.POST, "http://webapi.map10000.com:81/api/userinfo/putpassword", parameters: mydict)
        my.responseJSON { response in
            print("收到post数据responseJSON：----------");
            print(response.request)
            print(response.response)
            print(response.data)
            print(response.result)
            if let JSON = response.result.value {
                print("JSON:\(JSON)")
            }
        }
        
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

