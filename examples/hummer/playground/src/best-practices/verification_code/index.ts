import { Hummer, View, Text, Input, InputEvent } from '@hummer/hummer-front'
import { Color } from '../../common/CommonColor'

class RootView extends View {
    constructor() {
        super();
        this.style = {
            width: '100%',
            height: '100%',
            marginTop: 40,
            padding: 20,
        }

        let titleView = new Text();
        titleView.text = "获取验证码"
        titleView.style = {
            fontSize: 26,
            fontWeight: 'bold',
            color: Color.dark_grey,
        }

        let descView1 = new Text();
        descView1.text = "验证码已发送到您手机"
        descView1.style = {
            marginTop: 16,
        }
        let descView2 = new Text();
        descView2.text = "+86 15888888888"
        descView2.style = {
            marginTop: 16,
        }

        let verifyCodeView = new VerifyCodeView()
        verifyCodeView.style = {
            marginTop: 32,
        }

        this.appendChild(titleView);
        this.appendChild(descView1);
        this.appendChild(descView2);
        this.appendChild(verifyCodeView);
    }
}

class VerifyCodeView extends View {
    constructor() {
        super();
        this.style = {
            flexDirection: 'row',
            width: '90%',
            justifyContent: 'space-between',
        }

        let inputViews = new Array();
        for (let i = 0; i < 6; i++) {
            let input = new Input();
            input.style = {
                width: 40,
                height: 40,
                borderRadius: 6,
                borderWidth: 2,
                borderColor: Color.hm_green,
                textAlign: 'center',
                fontSize: 20,
                type: 'number',
                cursorColor: Color.hm_green,
                maxLength: 1,
            }

            input.addEventListener('input', (event: InputEvent) => {
                if (event.state == 2) { // 输入中
                    if (event.text) { // 有内容输入
                        if (i < inputViews.length - 1) {
                            inputViews[i + 1].focused = true;
                        } else {
                            inputViews[i].focused = false;
                        }
                    } else { // 无内容输入
                        if (i > 0) {
                            inputViews[i - 1].focused = true;
                        } else {
                            inputViews[0].focused = false;
                        }
                    }
                }
            })

            inputViews.push(input);
            this.appendChild(input);
        }
    }
}

Hummer.render(new RootView());